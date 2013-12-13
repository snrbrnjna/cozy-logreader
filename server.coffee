# 
# Express App for Displaying Server Log Files in the Browser and
# receiving some trigger commands through a websocket.
#

fs = require "fs"
spawn = require('child_process').spawn
ansispan = require 'ansispan'
require 'colors'

config = require './config'

# setup webserver express
express = require 'express'
engine = require 'ejs-locals'
routes = require './routes'
logs = require './routes/logs'
http = require 'http'
path = require 'path'

app = express()
# use ejs-locals for all ejs templates: enables stuff like layouts etc.
app.engine 'ejs', engine

# configure webserver for all environments
app.set 'port', config.port
app.set 'views', path.join(__dirname, 'views')
app.set 'view engine', 'ejs'
app.use app.router
app.use express.static(path.join(__dirname, 'public'))

# routes
app.get '/', routes.index
app.get '/logs', logs.index

# start http server
server = http.createServer(app).listen app.get('port'), () ->
  console.log 'express server listening on port ' + app.get('port') + ''.green

# init socket.io
io = require("socket.io").listen server
io.set 'log level', 2 # disable heartbeat debug output


# socket.io handlers for all messages
clients = {}
client_commands = {}
trigger_commands = {}
all_commands = []

# Send data to connected client.
sendData = (socket, data, fileName, fileSlug, channel) ->
  data = "#{data}"
  socket.emit 'new-data',
    'fileSlug': fileSlug
    'fileName': fileName
    'channel': channel
    'value': ansispan(data).replace /(\[[0-9]+m)*/g, ""


# Stop given commands by sending them a SIGTERM signal.
killCommands = (commands) ->
  for label, command of commands
    console.log "Killing process for #{label}..."
    command.kill 'SIGTERM'

# Kills all commands still in commands-cache and resets the cache
killAllCommands = () ->
  killCommands all_commands
  all_commands = []
  for client_id of client_commands
    killCommands client_commands[client_id]
  client_commands = {}

# Start process run a tail -f command on given file and redirect output to
# given socket.
startLogProcess = (socket, fileName, commands) ->
  console.log 'Start Log Process for ' + fileName
  
  # only tail, or pipe tail output to another process with easy-pipe
  args = ['-f', "#{config.logPath}/#{fileName}"]
  if (config.pipeLogOutputCmd)
    # tail -f logfile
    tail = spawn "tail", args
    # modify tail -f output with an extra command
    command = spawn config.pipeLogOutputCmd[0], config.pipeLogOutputCmd[1]
    # pipe tail output to command
    tail.stdout.pipe(command.stdin)
    tail.stderr.pipe(command.stdin)
    # save tail command as an extra child_process
    commands[fileName + '-tail'] = tail
  else
    command = spawn "tail", args

  # replace . by - to avoid conflicts in the frontend
  fileSlug = fileName.replace /\./g, '-'

  command.stdout.on 'data', (data) ->
    sendData(socket, data, fileName, fileSlug, 'stdout')
  command.stderr.on 'data', (data) ->
    sendData(socket, data, fileName, fileSlug, 'stderr')

  commands[fileName] = command

startStatusWatches = (socket) ->
  # every configured status cmd is executed in its own child_process
  cmds = config.statusCmd

  if cmds
    for cmd_key in Object.keys(cmds)
      startStatusWatch(cmds[cmd_key], cmd_key, socket)

startStatusWatch = (cmd, label, socket) ->
  console.log "Start Status Watch Processes for #{label}"
  console.log "#{label}: #{cmd}"

  command = spawn cmd, []
  command.stdout.on 'data', (data) ->
    io.sockets.emit 'status',
      key: label
      value: "#{data}"
  command.stderr.on 'data', (data) ->
    io.sockets.emit 'status',
      key: label
      value: "#{data}"

  all_commands["status_watch_#{label}"] = command


# Spawns a child process for given command unless there is currently one running
# for the same command
spawnCmd = (socket, cmd_key) ->
  if config[cmd_key]
    console.log("Command #{cmd_key} received")
    
    unless trigger_commands[cmd_key]
      console.log "... spawning child process for received command #{config[cmd_key]}".yellow
      command = spawn config.publishLiveCmd, []
      # command stdout
      command.stdout.on 'data', (data) ->
        # DEBUG
        # console.log("   ... #{cmd_key} stdout: #{data}")
      # command stderr
      command.stderr.on 'data', (data) ->
        # DEBUG
        # console.log("   ... #{cmd_key} stderr: #{data}")
      # When the child process finishes...
      command.on 'exit', (exit_code) ->
        console.log("... child process for #{cmd_key} terminated".green)
        trigger_commands[cmd_key] = null
  
      trigger_commands[cmd_key] = command
    else
      console.log "no, nothing i'm currently working on command #{cmd_key}, "+
                  "so i won't do nothing else, till this process has terminated"
  else
    console.log "command '#{cmd_key}' not found"

# Triggers a command if it matches with one of the below defined ones
trigger = (socket, msg) ->
  console.log("Received trigger with message '#{msg}' from client #{socket.id}")
  if msg == 'publish'
    spawnCmd(socket, 'publishLiveCmd')
  if msg == 'restart-preview'
    spawnCmd(socket, 'restartPreviewCmd')
    
    
# On connection, list all files in the log path directory and start redirecting
# a tail -f for each of them to given socket.
# When socket is disconnected, all tail -f process are stopped.
io.sockets.on "connection", (socket) ->

  # hold all connected clients
  clients[socket.id] = socket
  
  # Logging
  console.log "New client client #{socket.id} connecting...".cyan +     
              " (con ##{Object.keys(clients).length})"
  console.log "All connected clients:"
  console.log Object.keys(clients)
  
  # spawn tail -f child processes for every logfile, that is going to be 
  # watched
  commands = []
  fs.readdir config.logPath, (err, files) ->
    if !err
      for fileName in files
        startLogProcess(socket, fileName, commands)
    else
      console.log err
  # save reference to every child_process of current socket
  client_commands[socket.id] = commands
  
  # if client is the first one, spawn a child process to watch status of stage 
  # server
  unless Object.keys(clients).length > 1
    startStatusWatches socket


  # register a trigger receiver for triggers coming from the current client
  socket.on "trigger", (data) ->
    trigger(socket, data.msg)

  # register a cleaning taks, when the current client closes its connection
  socket.on "disconnect", () ->
    delete clients[socket.id]
    console.log "Client #{socket.id} is disconnecting...".cyan +
                " (#{Object.keys(clients).length} cons left)"
    killCommands client_commands[socket.id]
    delete client_commands[socket.id]
    console.log "All connected clients:"
    console.log Object.keys(clients)
    unless Object.keys(clients).length > 0
      console.log "All clients have disconnected killing all remaining " + 
                  "child_processes..."
      killAllCommands()


process.on 'SIGINT', () ->
    console.log "Server is stopping, closing the processes..."
    killAllCommands
    app.close()
    process.exit()

process.on 'SIGTERM', () ->
    console.log "Server is stopping, closing the processes..."
    killAllCommands
    app.close()

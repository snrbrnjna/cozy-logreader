#
# TODO: ansicolors
# TODO: when there's a directory in the logPath we print the error of the tail 
#       cmd into the log-tab in the browser: instead: ignore logPath entries, 
#       that are directories
#
fs = require "fs"
spawn = require('child_process').spawn
connect = require "connect"

config = require './config'

app = connect.createServer(connect.static('public')).listen(config.port)
console.log("connect server is up and listening on http://localhost:" +
  config.port + "...");
io = require("socket.io").listen app
io.set 'log level', 2 # disable heartbeat debug output

clients = {}
client_commands = {}
all_commands = []

# Send data to connected client.
sendData = (socket, data, fileName, fileSlug, channel) ->
    data = "#{data}"
    socket.emit 'new-data',
        'fileSlug': fileSlug
        'fileName': fileName
        'channel': channel
        'value': data.replace /(\[[0-9]+m)*/g, ""


# Stop given commands by sending them a SIGTERM signal.
killCommands = (commands) ->
    for fileName, command of commands
        console.log "Killing process for #{fileName}..."
        command.kill 'SIGTERM'


# Start process run a tail -f command on given file and redirect output to
# given socket.
startProcess = (socket, fileName) ->
    console.log 'Start Log Process for ' + fileName
    args = ['-f', "#{config.logPath}/#{fileName}"]
    command = spawn "tail", args

    # replace . by - to avoid conflicts in the frontend
    fileSlug = fileName.replace /\./g, '-'

    command.stdout.on 'data', (data) ->
        sendData(socket, data, fileName, fileSlug, 'stdout')
    command.stderr.on 'data', (data) ->
        sendData(socket, data, fileName, fileSlug, 'stderr')

    all_commands[socket.id + '-' + fileName] = command


startStatusWatches = (socket) ->
    # every configured status cmd is executed in its own child_process
    console.log config.statusCmd
    cmds = config.statusCmd
    for cmd_key in Object.keys(cmds)
      console.log "Start Status Watch Processes for #{cmd_key}"
      cmd = cmds[cmd_key]
      command = spawn cmd, []
      command.stdout.on 'data', (data) ->
          io.sockets.emit 'status',
              cmd_key: "#{data}"
      command.stderr.on 'data', (data) ->
          io.sockets.emit 'status',
              cmd_key: "#{data}"

      all_commands["status_watch_#{cmd_key}"] = command


# On connection, list all files in the log path directory and start redirecting
# a tail -f for each of them to given socket.
# When socket is disconnected, all tail -f process are stopped.
io.sockets.on "connection", (socket) ->

    # hold all connected clients
    clients[socket.id] = socket
    
    # Logging
    console.log "New client client #{socket.id} connecting" +     
      " (con ##{Object.keys(clients).length})"
    console.log "All connected clients:"
    console.log Object.keys(clients)
    
    # spawn tail -f child processes for every logfile, that is going to be 
    # watched
    commands = []
    fs.readdir config.logPath, (err, files) ->
        if !err
            for fileName in files
                commands[fileName] = startProcess(socket, fileName)
        else
            console.log err
    # save reference to every child_process of current socket
    client_commands[socket.id] = commands
    
    # if client is the first one, spawn a child process to watch status of stage 
    # server
    unless Object.keys(clients).length > 1
        startStatusWatches socket


    # register a trigger receiver for triggers coming from the current client
    # TODO: implement
    socket.on "trigger", (whot) ->
      console.log('something was triggered:')
      console.log(whot)

    # register a cleaning taks, when the current client closes its connection
    socket.on "disconnect", () ->
        console.log "Client #{socket.id} is disconnecting..."
        delete clients[socket.id]
        killCommands client_commands[socket.id]
        delete client_commands[socket.id]
        console.log "All connected clients:"
        console.log Object.keys(clients)
        unless Object.keys(clients).length > 0
            console.log "All clients have disconnected closing all remaining " +
              "child_processes..."
            killCommands all_commands

process.on 'SIGINT', () ->
    console.log "Server is stopping, closing the processes..."
    killCommands all_commands
    app.close()
    process.exit()

process.on 'SIGTERM', () ->
    console.log "Server is stopping, closing the processes..."
    killCommands all_commands
    app.close()

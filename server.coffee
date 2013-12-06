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
publish_command = null
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
startLogProcess = (socket, fileName) ->
    console.log 'Start Log Process for ' + fileName
    args = ['-f', "#{config.logPath}/#{fileName}"]
    command = spawn "tail", args

    # replace . by - to avoid conflicts in the frontend
    fileSlug = fileName.replace /\./g, '-'

    command.stdout.on 'data', (data) ->
        sendData(socket, data, fileName, fileSlug, 'stdout')
    command.stderr.on 'data', (data) ->
        sendData(socket, data, fileName, fileSlug, 'stderr')

    command

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


# Triggers the publish task unless there is currently one running yet
publish = (socket) ->
    console.log("Publish Command #{config.publishLiveCmd} received")
    
    unless publish_command
        console.log "... spawning child process for received publish Command #{config.publishLiveCmd}"
        publish_command = spawn config.publishLiveCmd, []
        # command stdout
        publish_command.stdout.on 'data', (data) ->
            # console.log("   ... publish stdout: #{data}")
        # command stderr
        publish_command.stderr.on 'data', (data) ->
            # console.log("   ... publish stderr: #{data}")
        # When the child process finishes...
        publish_command.on 'exit', (exit_code) ->
            console.log("... child process for publish terminated")
            publish_command = null
    
        publish_command
    else
        console.log "no, nothing i'm currently publishing, so i won't do nothing else, till this process has terminated"

# Triggers a command if it matches with one of the below defined ones
trigger = (socket, msg) ->
    console.log("Received trigger with message '#{msg}' from client #{socket.id}")
    if msg == 'publish'
        publish(socket)
    
    
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
                commands[fileName] = startLogProcess(socket, fileName)
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
        console.log "Client #{socket.id} is disconnecting..."
        delete clients[socket.id]
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

# Handler to display the test html file
handler = (req, res) ->
    data = fs.readFileSync('index.html');
    res.writeHead 200
    res.end data
# ./handler

app = require("http").createServer(handler)
io = require("socket.io").listen(app)
io.set 'log level', 2 # disable heartbeat debug output
fs = require "fs"
config = require './config'
spawn = require('child_process').spawn

app.listen 9099

io.sockets.on "connection", (socket) ->

    commands = []

    fs.readdir config.logPath, (err, files) ->

        if !err
            for fileName in files
                args = ['-f', "#{config.logPath}/#{fileName}"]
                command = spawn "tail", args
                commands.push(command)

                # replace . by - to avoid conflicts in the frontend
                fileSlug = fileName.replace /\./g, '-'

                sendData = (data) ->
                    socket.emit 'new-data',
                        'fileSlug': fileSlug
                        'fileName': fileName
                        'channel': 'stderr'
                        'value': "#{data}"

                command.stdout.on 'data', sendData
                command.stderr.on 'data', sendData
        else
            console.log err

    socket.on "disconnect", () ->
        console.log "Client has disconnected, closing the processes..."
        for command in commands
            command.kill 'SIGTERM'

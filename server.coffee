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
            for filename in files
                args = ['-f', "#{config.logPath}/#{filename}"]
                command = spawn "tail", args
                commands.push(command)

                command.stdout.on 'data',  (data) ->
                    socket.emit 'new-data',
                        'file': filename
                        'channel': 'stdout'
                        'value': "#{data}"

                command.stderr.on 'data', (data) ->
                    socket.emit 'new-data',
                        'file': filename
                        'channel': 'stderr'
                        'value': "#{data}"
        else
            console.log err

    socket.on "disconnect", () ->
        console.log "Client has disconnected, closing the processes..."
        for command in commands
            command.kill 'SIGTERM'

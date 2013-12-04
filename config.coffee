require "js-yaml"

config = 
  logPath: '../fake.log'
  port: 9099

try
  yaml = require('../_config.env.yml')
  if yaml
    config['logPath'] = yaml.preview_logspath
    config['port'] = yaml.local_control_port
    
catch error
  console.warn("Ignoring local env config, because the file _config.env.yml " +    
               "doesn't exists")
  console.warn(error)

module.exports = config

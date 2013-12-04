require "js-yaml"

config = 
  logPath: ''
  port: 9099

try
  yaml = require('../_config.env.yml')
  if yaml
    config['logPath'] = yaml.preview_logspath
catch error
  console.warn("Ignoring local env config, because the file _config.env.yml " +    
               "doesn't exists")
  console.warn(error)

module.exports = config

var config = require('../config');

exports.index = function(req, res){
  var title = 'notwist.com log-monitor';
  
  res.render('logs', { title: title, socket_url: config.url });
};
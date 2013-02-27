var serverOption = require('../etc/config/server-config.json').serverDetails;
var dataPath = require('../etc/config/paths-config.json').dataPath;
var Sqlite3 = require('./sqlite-wrapper.js');
var global = require('./global.js');
var updateConfig = require('./update-config.js');
var authenticate = require('./authentication.js');

var Sealion = { };
var needCheckStoredData = true;


Sealion.SendData = function (sqliteObj) {
    this.dataToInsert = '';
    this.sqliteObj = sqliteObj;
    this.activityID = '';
};

Sealion.SendData.prototype.handleError = function() {
    this.sqliteObj.insertData(this.dataToInsert, this.activityID);
    needCheckStoredData = true;
}

Sealion.SendData.prototype.handleErroneousData = function( ) {
    this.sqliteObj.insertErroneousData(this.dataToInsert, this.activityID);
}


Sealion.SendData.prototype.sendStoredData = function() {
    var sobj = new Sqlite3();
    var db = sobj.getDb();
    var tempThis = this;
    
    if(db) {
        db.all('SELECT row_id, activityID, date_time, result FROM repository LIMIT 0,1', function(error, rows) {
            
            if(error) {
                needCheckStoredData = true;
                console.log("error in retreiving data");
            } else {
                if(rows.length > 0) {
                    
                    var path = dataPath + rows[0].activityID;
                    var url = serverOption.sourceURL + path;
                    var toSend = JSON.parse(rows[0].result);
                    
                    var sendOptions = {
                          'uri' : url
                        , 'json' : toSend
                    };
                    
                    global.request.post(sendOptions, function(err, response, data) {
                        if(err) {
                            needCheckStoredData = true;
                            console.log("Error in Sending stored data");
                        } else {
                            if(response.statusCode === 200) {
                                var tempSqliteObj = new Sqlite3();
                                var tempDB = tempSqliteObj.getDb();
                                tempDB.run('DELETE FROM repository WHERE row_id = ?', rows[0].row_id, function(error){
                                    if(error) {
                                        console.log("error in deleting data from DB");
                                    } else {
                                        process.nextTick(function () {
                                            tempThis.sendStoredData();
                                        });
                                    }
                                });
                                tempSqliteObj.closeDb();
                            } else {
                                needCheckStoredData = true;
                            }
                        }
                    });
                } else {
                    needCheckStoredData = false;
                }
            }
        });
        sobj.closeDb();
    }
}

Sealion.SendData.prototype.dataSend = function (result) {
    var tempThis = this;
    
    var toSend = {
                  'returnCode' : result.code
                , 'timestamp' : result.timeStamp
                , 'data' : result.output };
                
    this.dataToInsert = JSON.stringify(toSend);
    this.activityID = result.activityDetails._id;
    
    var path = dataPath + result.activityDetails._id;
    var url = serverOption.sourceURL + path;
    var sendOptions = {
          'uri' : url
        , 'json' : toSend
    };
    
    global.request.post(sendOptions, function(err, response, data) {
        
        if(err) {
            console.log(err);
            tempThis.handleError();
        } else {
            var bodyJSON = response.body;

            switch(response.statusCode) {
                case 200 : {
                        if(needCheckStoredData) {
                            needCheckStoredData = false;
                            tempThis.sendStoredData();
                        }    
                    }
                    break;
                case 400 : {
                        if(bodyJSON.code) {
                            switch(bodyJSON.code) {
                                case 230011 : {
                                        console.log('Sealion-Agent Error#430001: Payload Missing');
                                        tempThis.handleErroneousData();
                                    }
                                    break;
                                case 230014 : {
                                        console.log('Sealion-Agent Error#430002: improper ActivityID, updating config-file');
                                        updateConfig();
                                    }
                                    break;
                                default : {
                                        tempThis.handleError();    
                                    }
                            }
                        } else {
                            tempThis.handleError();
                        }
                    }
                    break;
                case 401 : {
                        if(bodyJSON.code) {
                            switch(bodyJSON.code) {
                                case 230012 : {
                                        console.log('Sealion-Agent Error#430003: Agent not allowed to send data with ActivityID: ' + result.activityDetails._id + ', updating config-file');
                                            updateConfig();
                                    }
                                    break;
                                case 220001 : {
                                        console.log('Sealion-Agent Error#430005: Authentication Failed, Needs reauthentication');
                                        authenticate.reauthenticate();
                                    }
                                    break;
                                default : {
                                        tempThis.handleError();
                                    }
                                    break;
                            }    
                        } else {
                            tempThis.handleError();
                        }
                    }
                    break;
                case 409 : {
                        console.log('Sealion-Agent Error#430004: Duplicate data. Data dropped');                   
                    }
                    break;
                default: {
                        tempThis.handleError();    
                    }
                    break;
            }
        }
    });
}

module.exports = Sealion.SendData;

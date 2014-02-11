import os
import json
import re
import threading
from constructs import *
   
class Utils(Namespace):
    @staticmethod
    def sanitize_type(d, schema, is_delete_extra = True, regex = None, is_regex = False):
        type_name = type(d).__name__

        if type_name == 'dict' and type(schema) is dict:
            return Utils.sanitize_dict(d, schema, is_delete_extra)
        elif type_name == 'list' and type(schema) is list:
            for i in range(0, len(d)):
                if Utils.sanitize_type(d[i], schema[0], is_delete_extra, regex) == False:
                    return False
                
            return True
        else:
            types = schema.split(',')
            flag = False
            
            for i in range(0, len(types)):
                if type_name == types[i]:
                    flag = True
                    break
                    
            if flag == True and (type_name == 'str' or type_name == 'unicode'):
                if regex != None and re.match(regex, d) == None:
                    return False
                elif is_regex == True:
                    try:
                        re.compile(d)
                    except:
                        return False
                
            return flag

    @staticmethod
    def sanitize_dict(d, schema, is_delete_extra = True):
        ret = 1

        if is_delete_extra == True:  
            keys = d.keys()
            
            if schema.has_key('.') and len(schema.keys()) == 1 and len(keys) == 1:
                temp = {}
                temp[keys[0]] = schema['.']
                schema = temp

            for i in range(0, len(keys)):
                if schema.has_key(keys[i]) == False:
                    del d[keys[i]]
                    continue

        depends_check_keys = []

        for key in schema:
            is_optional = schema[key].get('optional', False)

            if d.has_key(key) == False:
                ret = 0 if is_optional == False else ret
            else:
                if schema[key].has_key('depends') == True:
                    depends_check_keys.append(key)

                if Utils.sanitize_type(d[key], schema[key]['type'], is_delete_extra, 
                                        schema[key].get('regex'), schema[key].get('is_regex', False)) == False:
                    del d[key]
                    ret = 0 if is_optional == False else ret                

        for j in range(0, len(depends_check_keys)):
            depends = schema[depends_check_keys[j]]['depends']

            for i in range(0, len(depends)):
                if d.has_key(depends[i]) == False:
                    if d.has_key(depends_check_keys[j]):
                        del d[depends_check_keys[j]]
                        
                    break

        return False if ret == 0 else True

    @staticmethod
    def get_safe_path(path):
        dir = os.path.dirname(path)

        if os.path.isdir(dir) != True:
            os.makedirs(dir)

        return path    
         
class Config:
    def __init__(self):
        self.schema = {}
        self.file = ''
        self.data = {}
        self.lock = threading.RLock()
        
    def __getattr__(self, attr):
        self.lock.acquire()
        
        try:
            return self.data[attr]
        finally:
            self.lock.release()
        
    def get_dict(self, keys = None, as_dict = True):
        self.lock.acquire()
        
        try:
            return DictEx(self.data).get_dict(keys, as_dict)
        finally:
            self.lock.release()
        
    @staticmethod
    def parse(file, is_data = False):
        value = {}

        if is_data == True or os.path.isfile(file) == True:        
            try:
                data = file

                if is_data != True:
                    f = open(file, 'r')
                    data = f.read()
                    f.close()
                    data = re.sub('#.*\n', '', data)
                    value = json.loads(data)
                elif type(data) is dict:
                    value = data
                else:
                    data = re.sub('#.*\n', '', data)
                    value = json.loads(data)
            except:
                pass

        return value
        
    def save(self):
        self.lock.acquire()
        
        try:
            f = open(self.file, 'w')
            json.dump(self.data, f)
            f.close()
            return True
        except:
            return False
        finally:
            self.lock.release()
            
    def set(self, data = None):
        is_data = True
        
        if data == None:            
            data = self.file
            is_data = False
            
        config = Config.parse(data, is_data)
        
        if Utils.sanitize_dict(config, self.schema) == False:
            if is_data == False:
                return self.file + ' is either missing or currupted'
            else:
                return 'Invalid config'
            
        self.lock.acquire()
        self.data = config
        self.lock.release()
        return True
        
    def update(self, data):
        config = {}
        self.lock.acquire()
        config.update(self.data)
        self.lock.release()
        config.update(Config.parse(data, True))
        return self.set(config)
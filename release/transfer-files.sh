VERSION="-v"`cat ../build/version`
SERVER="192.168.1.70"
INSTALLER_HELPER_PATH=/var/www/sealion.com/downloads/
INSTALLER_PATH=/var/www/sealion.com/downloads/
USER="vishal"
PWD="cameo15jay"

#pscp -l $USER -pw $PWD sealion.sh $SERVER:$INSTALLER_HELPER_PATH
#pscp -l $USER -pw $PWD r $SERVER:$INSTALLER_PATH
#pscp -l $USER -pw $PWD update.sh $SERVER:$UPDATE_PATH

scp -i ./sealion-testkey.pem ./sealion.sh ec2-user@test.sealion.com:/usr/local/sealion/agent/release/
scp -i ./sealion-testkey.pem ./installer.sh ec2-user@test.sealion.com:/usr/local/sealion/agent/release/

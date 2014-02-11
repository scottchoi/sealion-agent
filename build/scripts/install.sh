#!/bin/bash

#check platform compatibility
if [ "`uname -s`" != "Linux" ] ; then
    echo 'Error: SeaLion agent works on Linux only' >&2
    exit 1
fi

#check for platform architecture
PLATFORM=`uname -m`

if [[ "$PLATFORM" != 'x86_64' && "$PLATFORM" != 'i686' ]] ; then
    echo "Error: Platform not supported" >&2
    exit 1
fi

#check for kernel version (min 2.6)
eval $(uname -r | awk -F'.' '{printf("KERNEL_VERSION=%s KERNEL_MAJOR=%s\n", $1, $2)}')

if [ $KERNEL_VERSION -le 2 ] ; then
    if [[ $KERNEL_VERSION -eq 1 || $KERNEL_MAJOR -lt 6 ]] ; then
        echo "Error: SeaLion agent requires kernel 2.6 or above" >&2
        exit 1
    fi
fi

#check for python (min 2.6)
PYTHON=0

case "$(python --version 2>&1)" in
    *" 3."*)
        PYTHON=1
        ;;
    *" 2.6."*)
        PYTHON=1
        ;;
    *" 2.7."*)
        PYTHON=1
        ;;
esac

if [ $PYTHON -eq 0 ] ; then
    echo "Error: SeaLion agent requires python version 2.6 or above" >&2
    exit 1
fi

#config variables
API_URL="<api-url>"
UPDATE_URL="<agent-download-url>"
VERSION="<version>"

#script variables
BASEDIR=$(readlink -f "$0")
BASEDIR=$(dirname $BASEDIR)
BASEDIR=${BASEDIR%/}
USER_NAME="sealion"
IS_UPDATE=1
INIT_FILE="sealion.py"
DEFAULT_INSTALL_PATH="/usr/local/sealion-agent"
INSTALL_AS_SERVICE=1

#setup variables
INSTALL_PATH=$DEFAULT_INSTALL_PATH
ORG_TOKEN=
CATEGORY=
HOST_NAME=$(hostname)
PROXY=$https_proxy

update_agent_config()
{
    ARGS="-i 's/\(\"$1\"\s*:\s*\)\(\"[^\"]\+\"\)/\1\"$2\"/'"
    eval sed "$ARGS" $INSTALL_PATH/etc/config/agent.json
}

install_service()
{
    RC1_PATH=`find /etc/ -type d -name rc1.d`
    RC2_PATH=`find /etc/ -type d -name rc2.d`
    RC3_PATH=`find /etc/ -type d -name rc3.d`
    RC4_PATH=`find /etc/ -type d -name rc4.d`
    RC5_PATH=`find /etc/ -type d -name rc5.d`
    RC6_PATH=`find /etc/ -type d -name rc6.d`
    INIT_D_PATH=`find /etc/ -type d -name init.d`
    SYMLINK_PATHS=(K K S S S S K)

    if [[ -z $RC1_PATH || -z $RC2_PATH || -z $RC3_PATH || -z $RC4_PATH || -z $RC5_PATH || -z $RC6_PATH || -z $INIT_D_PATH ]] ; then
        echo "Error: Cannot create service. Could not locate init.d/rc directories" >&2
        return 1
    fi
    
    ln -sf $SERVICE_FILE $INIT_D_PATH/sealion
    chmod +x $SERVICE_FILE
    
    for (( i = 1 ; i < 7 ; i++ )) ; do
        VAR_NAME="RC"$i"_PATH"
        ln -sf $SERVICE_FILE ${!VAR_NAME}/${SYMLINK_PATHS[$i]}99sealion
        
        if [ $? -ne 0 ] ; then
            echo "Error: Cannot create service. Unable to update init.d files" >&2
            return 1
        fi
    done
    
    return 0
}

while getopts i:o:c:H:x: OPT ; do
    case "$OPT" in
        i)
            INSTALL_PATH=$OPTARG
            ;;
        o)
            ORG_TOKEN=$OPTARG
            ;;
        c)
            CATEGORY=$OPTARG
            ;;
        H)
            HOST_NAME=$OPTARG
            ;;
        x)
            PROXY=$OPTARG
            ;;
        \?)
            echo "Invalid argument -$OPTARG" >&2
            exit 126
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            exit 125
            ;;
    esac
done

INSTALL_PATH=${INSTALL_PATH%/}

if [ "$INSTALL_PATH" != "$DEFAULT_INSTALL_PATH" ] ; then
    INSTALL_AS_SERVICE=0
fi

SERVICE_FILE="$INSTALL_PATH/etc/sealion"

if [ "$ORG_TOKEN" != '' ] ; then
    if [[ $EUID -ne 0 ]]; then
        echo "Error: You need to run this as root user" >&2
        exit 1
    fi

    IS_UPDATE=0

    #create installation dir
    mkdir -p $INSTALL_PATH

    if [ $? -ne 0 ] ; then
        echo "Error: Cannot create installation directory" >&2
        exit 118
    fi

    #create sealion group
    id -g $USER_NAME >/dev/null 2>&1

    if [ $? -ne 0 ] ; then
        groupadd -r $USER_NAME >/dev/null 2>&1
        
        if [ $? -ne 0 ] ; then
            echo "Error: Cannot create $USER_NAME group" >&2
            exit 1
        fi
    fi

    #create sealion user
    id $USER_NAME >/dev/null 2>&1

    if [ $? -ne 0 ] ; then
        useradd -r -g $USER_NAME $USER_NAME >/dev/null 2>&1
        
        if [ $? -ne 0 ] ; then
            echo "Error: Cannot create $USER_NAME user" >&2
            exit 1
        fi
    fi
else
    if [ ! -f "$INSTALL_PATH/$INIT_FILE" ] ; then
        echo "Error: $INSTALL_PATH is not a valid sealion directory"
        exit 1
    fi
fi

if [ -f "$INSTALL_PATH/$INIT_FILE" ] ; then
    echo "Stopping agent..."
    python $INSTALL_PATH/$INIT_FILE stop
fi

echo "Copying files..."

if [ $IS_UPDATE -eq 0 ] ; then
    cp -r $BASEDIR/agent/* $INSTALL_PATH
    CONFIG="\"orgToken\": \"$ORG_TOKEN\", \"apiUrl\": \"$API_URL\", \"updateUrl\": \"$UPDATE_URL\", \"agentVersion\": \"$VERSION\", \"name\": \"$HOST_NAME\""

    if [ "$CATEGORY" != "" ] ; then
        CONFIG="$CONFIG, \"category\": \"$CATEGORY\""
    fi
        
    echo "{$CONFIG}" >$INSTALL_PATH/etc/config/agent.json

    if [ "$PROXY" != "" ] ; then
        PROXY="$(echo "$PROXY" | sed 's/[^-A-Za-z0-9_]/\\&/g')"
        ARGS="-i 's/\(\"env\"\s*:\s*\[\)/\1{\"https\_proxy\": \"$PROXY\"}/'"
        eval sed "$ARGS" $INSTALL_PATH/etc/config/sealion.json
    fi

    chown -R $USER_NAME:$USER_NAME $INSTALL_PATH    
    echo "Sealion agent installed successfully"    

    if [ $INSTALL_AS_SERVICE -eq 1 ] ; then
        echo "Creating service"
        install_service
    fi
else
    find $BASEDIR/agent/ -mindepth 1 -maxdepth 1 -type d ! -name 'etc' -exec cp -r {} $INSTALL_PATH \;
    update_agent_config "agentVersion" $VERSION
    update_agent_config "apiUrl" $API_URL
    update_agent_config "updateUrl" $UPDATE_URL
    echo "Sealion agent updated successfully"
fi

echo "Starting agent..."
python $INSTALL_PATH/$INIT_FILE start


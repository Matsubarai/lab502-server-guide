#!/bin/bash
EXC="true"
PUB="false"
VNC_ENABLE="false"
JUPYTER_ENABLE="false"
IMG="xilinx-u280:latest"
while getopts ":d:p:i:v:eh" optname
do
	case "$optname" in
		"d")
			DEVICE=$OPTARG
			;;
		"e")
			EXC="false"
			;;
                "p")
			if [ $EXPOSE_PORT ]
			then
				echo "only one APP can be exposed"
				exit 1
   			fi
                        PUB="true"
			APP=$OPTARG
			if [ $APP = "jupyter" ]
			then
				EXPOSE_PORT=8888
				JUPYTER_ENABLE="true"
			elif [ $APP = "vnc" ]
			then
				EXPOSE_PORT=6901
				VNC_ENABLE="true"
			else
				echo "Unknown APP $APP"
				exit 1
			fi
			;;
		"i")
			IMG="$OPTARG"
			;;
		"v")
			MNT="$MNT -v $OPTARG" 
			;;
		"h")
			echo "USAGE: env_alloc [-d <DeviceID[,...]=NULL>] [-e (NO_EXCLUSION_FLAG)] [-p <APP=jupyter|vnc>] [-i <IMAGE_NAME>]"
			exit 0
			;;
		":")
			echo "No argument value for option -$OPTARG"
			exit 1
			;;
		"?")
			echo "Unknown option $OPTARG"
			exit 1
			;;
		*)
			echo "Unknown error while processing options"
			exit 1
			;;
	esac
done
if [ $MNT ]
then
	echo "custom mount point:$MNT"
fi
FLAGS="--label owner=$USER --name $USER-env --runtime=xilinx -v /usr/local/MATLAB:/usr/local/MATLAB -v /home/$USER:/data -v /usr/local/etc:/usr/local/etc -v /tools:/tools:ro -e XILINX_VISIBLE_DEVICES=$DEVICE -e XILINX_DEVICE_EXCLUSIVE=$EXC -e VNC_ENABLE=$VNC_ENABLE -e JUPYTER_ENABLE=$JUPYTER_ENABLE -e USER=$USER $MNT"

docker inspect $USER-env > /dev/null 2>&1
if [ $? -eq 0 ]
then
	echo "Environment exists. You can execute or deallocate it."
	exit 0
fi

if [ $PUB = "true" ]
then
	PORT=`head -n 1 /usr/local/etc/port_pool`
	cp /usr/local/etc/port_pool ./.port_pool.temp
	sed -i '1d' ./.port_pool.temp
	cat ./.port_pool.temp > /usr/local/etc/port_pool
	rm ./.port_pool.temp

	if [ $PORT ]
	then
		echo "Publish $APP port $EXPOSE_PORT/tcp -> localhost:$PORT"
		docker run -d -p $PORT:$EXPOSE_PORT -e PORT=$PORT $FLAGS $IMG
	else
		echo "No valid port for publishing, use a random port"
		docker run -d -P $FLAGS $IMG
	fi
else
	echo "In command-line mode"
	docker run -d $FLAGS $IMG init
fi

if [ $? -ne 0 ]
then
	if [ $PORT ]
	then
		echo $PORT >> /usr/local/etc/port_pool
	fi
	exit 1
fi

if [ $DEVICE ]
then
	at -f /usr/local/bin/env_dealloc now +2 hours 2>&1 | grep -o '[0-9]\+' | head -1 > /usr/local/etc/timer_id.$USER
	echo "Allocated devices $DEVICE will be released after 2 hours."
fi

docker exec -it $USER-env /bin/bash

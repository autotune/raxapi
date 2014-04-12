#!/bin/bash

DIR=/home/images
DATACENTER="dfw"
IMAGEID=""
CONTAINER="exports"
# TASK=""

if [[ ! -e $DIR ]];
then
	echo "Creating $DIR"
	mkdir $DIR
	mkdir $DIR/tmp
fi


if [[ ! -e $DIR/conf/creds.cfg ]];
then
	echo -n "Username: " 
	read USERNAME
	
	echo -n "API key: "
	read APIKEY

	echo -n "Save Credintials? [y/n]: "
	read SAVE
	
	if [[ "$SAVE" == "y" ]];
	then
		mkdir "$DIR/conf"
		touch "$DIR/conf/creds.cfg"
		echo $USERNAME >> $DIR/conf/creds.cfg
		echo $APIKEY >> $DIR/conf/creds.cfg
	elif [[ "$SAVE" == "n" ]];
	then
		echo "Not saving..."	
	else
		echo "Must be 'y' or 'n'" 
		exit
	fi
	
	else
		echo "Reading $DIR/conf/creds..."
		USERNAME="$(cat $DIR/conf/creds.cfg|head -n1)"
		APIKEY="$(cat $DIR/conf/creds.cfg|tail -n1)"
fi

echo -n "Image ID: " 
read IMAGEID

curl -s -d \
"{
\"auth\":
{
\"RAX-KSKEY:apiKeyCredentials\":
{
\"username\":\"$USERNAME\",
\"apiKey\": \"$APIKEY\"}
}
}" \
-H 'Content-Type: application/json' \
'https://identity.api.rackspacecloud.com/v2.0/tokens' | python -m json.tool > $DIR/tmp/auth.txt

# grab auth token
grep "id" $DIR/tmp/auth.txt|awk '{print $2}'|head -n1|tr ',"' ' '|awk '{print $1}'  > $DIR/tmp/token.txt

TOKEN="$(cat $DIR/tmp/token.txt)"

echo "Auth token is: $TOKEN"

sleep 2

# curl -XGET -H "X-Auth-Token:  $TOKEN" -H "Content-type: application/json" https://$DATACENTER.images.api.rackspacecloud.com/v2/$ACCOUNT/tasks/$TASK | python -m json.tool

sleep 3

echo "Generating image..."

DATA="{\"type\": \"export\",\"input\":{\"image_uuid\": \"$IMAGEID\",\"receiving_swift_container\": \"$CONTAINER\"}}"


curl -s -X POST -H "X-Auth-Token: $TOKEN" -H "Content-Type: application/json" -H "Accept: application/json" --data "$DATA" https://$DATACENTER.images.api.rackspacecloud.com/v2/$ACCOUNT/tasks > $DIR/tmp/images.txt

echo "$CONTAINER ID: $(cat $DIR/tmp/images.txt|awk '{print $8}'|tr '",' ' '|awk '{print $1}')"



#!/bin/bash
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.


DIR=/home/images
DATACENTER="iad"
IMAGEID=""
CONTAINER="exported-images"
TASK=""

if [[ $TASK == "" ]]
then
	echo "Task ID required"
	exit
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

echo "Checking status..."

curl -XGET -H "X-Auth-Token:  $TOKEN" -H "Content-type: application/json" https://$DATACENTER.images.api.rackspacecloud.com/v2/$ACCOUNT/tasks/$TASK | python -m json.tool

exit




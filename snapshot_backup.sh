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


DIR=/root/storage
DATACENTER="ord"
SNAP_RET=2
SNAP_DEL=1 
VOL_ID=""
SNAP_NAME=""

if [[ ! -e "$DIR/tmp" ]];
then
	if [[ ! -e "$DIR" ]];
	then
		echo "Creating $DIR"
		mkdir $DIR
	fi
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

if [[ ! -e $DIR/tmp/snapshot_data.tmp ]];
then
	touch $DIR/tmp/snapshot_data.tmp
fi

if [[ ! -e $DIR/tmp/snapshot_ids.tmp ]];
then
        touch $DIR/tmp/snapshot_ids.tmp
fi

if [[ ! -e $DIR/tmp/snapshot_ids2.tmp ]];
then
        touch $DIR/tmp/snapshot_ids2.tmp
fi

if [[ ! -e $DIR/tmp/snapshots_created.tmp ]];
then
        touch $DIR/tmp/snapshots_created.tmp
fi

# replace and move with blank snapshot IDs back to snapshots_created.tmp after deletion 
if [[ ! -e $DIR/tmp/snapshots_created2.tmp ]];
then
        touch $DIR/tmp/snapshots_created2.tmp
fi

if [[ ! -e $DIR/tmp/snapshots_status.tmp ]];
then
        touch $DIR/tmp/snapshots_status.tmp
fi

if [[ -e $DIR/tmp/snapshots_created.tmp.gz  ]];
then
 	gunzip -f $DIR/tmp/snapshots_created.tmp.gz;
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

# grab ddi
TENANT_ID="$(grep "blockstorage" $DIR/tmp/auth.txt|awk '{print $2}'|tr '"/,' ' '|awk '{print $4}'|head -n1)"
echo "Tenant ID is: $TENANT_ID"

AUTH_ENDPOINT="https://$DATACENTER.blockstorage.api.rackspacecloud.com/v1/$TENANT_ID"
# echo "Auth Enpoint is: $AUTH_ENDPOINT"

sleep 2

# create snapshot
# will definitely have to refactor this at some point 
function createSnapshots()
{
  echo "Creating snapshot..."
  curl "https://$DATACENTER.blockstorage.api.rackspacecloud.com/v1/$TENANT_ID/snapshots" \
  -X POST \
  -H "X-Auth-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "
       {
         \"snapshot\": {
         \"display_name\": \"$SNAP_NAME $(date)\",
         \"display_description\": \"Daily backup\",
         \"volume_id\": \"$VOL_ID\",
         \"force\": true
       }
     }
   " | python -mjson.tool >> $DIR/tmp/snapshots_created.tmp

}

function listSnapshots()
{
  # rather than check against the current list in Cloud Control, check only those created
  SNAP_NUM="$(grep -w 'id' tmp/snapshots_created.tmp|awk '{print $2}'|tr '",' ' '|awk '{print $1}'|wc -l)"
  SNAPS="$(grep -w 'id' $DIR/snapshots_created.tmp|awk '{print $2}'|tr '",' ' '|awk '{print $1}')"
  echo "$SNAPS" > $DIR/tmp/snapshot_ids.tmp

  for ((id=1; id<=$SNAP_NUM; id++))
  do
  SNAP_ID=$(cat $DIR/tmp/snapshot_ids.tmp|awk "NR==$id")
  if [[ ! -e $DIR/tmp/snapshot_$SNAP_ID.tmp ]];
  then
    touch $DIR/tmp/snapshot_$SNAP_ID.tmp
  fi
  curl "https://$DATACENTER.blockstorage.api.rackspacecloud.com/v1/$TENANT_ID/snapshots/$SNAP_ID" \
  -H "X-Auth-Token: $TOKEN" \
  -H "Content-Type: application/json" | python -mjson.tool > $DIR/tmp/snapshot_$SNAP_ID.tmp
  done
}


# update status of each snapshot being deleted save1
# check created snapshots, grab the snapshot id, update with status of snapshot
function statusSnapshots()
{
  SNAP_NUM="$(grep -w 'id' $DIR/tmp/snapshots_created.tmp|awk '{print $2}'|tr '",' ' '|awk '{print $1}'|wc -l)"
  SNAPS="$(grep -w 'id' $DIR/tmp/snapshots_created.tmp|awk '{print $2}'|tr '",' ' '|awk '{print $1}')"

  echo "$SNAPS" > $DIR/tmp/snapshot_ids.tmp
  for ((id=1; id<=$SNAP_NUM; id++))
  do
     SNAP_ID=$(cat $DIR/tmp/snapshot_ids.tmp|awk "NR==$id")
     echo "Updating $DIR/tmp/snapshot_$SNAP_ID.tmp"
     if [[ ! -e "$DIR/tmp/snapshot_$SNAP_ID.tmp" ]];
     then
       touch $DIR/tmp/snapshot_$SNAP_ID.tmp
     fi
     curl "https://$DATACENTER.blockstorage.api.rackspacecloud.com/v1/$TENANT_ID/snapshots/$SNAP_ID" \
     -H "X-Auth-Token: $TOKEN" \
     -H "Content-Type: application/json" | python -mjson.tool > $DIR/tmp/snapshot_$SNAP_ID.tmp
  done

  STATUS="$(cat $DIR/tmp/snapshot_$SNAP_ID.tmp|grep status|awk '{print $2}'|tr '",' ' ' |awk '{print $1}')"
   
  # if there are any errors with snapshots outside those created by script, they will appear here
  while [[ "$STATUS" != "available" ]]
  do
    STATUS="$(cat $DIR/tmp/snapshot_$SNAP_ID.tmp|grep status|awk '{print $2}'|tr '",' ' ' |awk '{print $1}')"
    # statusSnapshots
    # assume if snapshot has 404'd it is has been deleted
    if [[ "$(cat $DIR/tmp/snapshot_$SNAP_ID.tmp|grep code|awk '{print $2}'|tr ',' ' ')" == *"404"* ]];
    then
      echo "$SNAP_ID is deleted"
      # rm -fr $DIR/tmp/snapshot_$SNAP_ID.tmp
      # delete line with snapshot ID so script no longer looks for it
      sed "/"$SNAP_ID"/d" $DIR/tmp/snapshots_created.tmp > $DIR/tmp/snapshots_created2.tmp && mv $DIR/tmp/snapshots_created2.tmp $DIR/tmp/snapshots_created.tmp
      sed "/"$SNAP_ID"/d" $DIR/tmp/snapshot_ids.tmp > $DIR/tmp/snapshot_ids2.tmp && mv $DIR/tmp/snapshot_ids2.tmp $DIR/tmp/snapshot_ids.tmp
      break;
    elif [[ ! -e $DIR/tmp/snapshot_$SNAP_ID.tmp ]];
    then
      continue;
    else
      clear
      echo "Snapshot $SNAP_ID is $(cat $DIR/tmp/snapshot_$SNAP_ID.tmp|grep status|awk '{print $2}'|tr ',' ' ')"
      echo "Snapshot progress: $(cat $DIR/tmp/snapshot_$SNAP_ID.tmp|grep progress|awk '{print $2}'|tr ',' ' ')"
      sleep 5
      curl "https://$DATACENTER.blockstorage.api.rackspacecloud.com/v1/$TENANT_ID/snapshots/$SNAP_ID" \
           -H "X-Auth-Token: $TOKEN" \
           -H "Content-Type: application/json" | python -mjson.tool > $DIR/tmp/snapshot_$SNAP_ID.tmp     
     fi
  done 
}


# we only want to delete snapshots created by the script in snapshot_ids.tmp
# so loop through each snapshot id, check for its current status, and delete
# only if available. 

function deleteSnapshots()
{
  SNAP_NUM="$(tail -n$SNAP_DEL $DIR/tmp/snapshot_ids.tmp|wc -l)"
  for ((id=1; id<="$SNAP_NUM"; id++))
  do
  SNAP_ID=$(tail -n1 $DIR/tmp/snapshot_ids.tmp|awk "NR==$id")
  STATUS="$(cat $DIR/tmp/snapshot_$SNAP_ID.tmp|grep status|awk '{print $2}'|tr '",' ' ' |awk '{print $1}')"
  while [[ "$STATUS" != "available" ]]
  do
    STATUS="$(cat $DIR/tmp/snapshot_$SNAP_ID.tmp|grep status|awk '{print $2}'|tr '",' ' ' |awk '{print $1}')"
    echo "Deleting $SNAP_ID after all are available..."
    statusSnapshots 
    # assume if snapshot has 404'd it is has been deleted
    if [[ "$(cat $DIR/tmp/snapshot_$SNAP_ID.tmp|grep code|awk '{print $2}'|tr ',' ' ')" == *"404"* ]];
    then
      echo "$SNAP_ID is deleted"
      # rm -fr $DIR/tmp/snapshot_$SNAP_ID.tmp
      # delete line with snapshot ID so script no longer looks for it
      sed "/"$SNAP_ID"/d" $DIR/tmp/snapshots_created.tmp > $DIR/tmp/snapshots_created2.tmp && mv $DIR/tmp/snapshots_created2.tmp $DIR/tmp/snapshots_created.tmp
      sed "/"$SNAP_ID"/d" $DIR/tmp/snapshot_ids.tmp > $DIR/tmp/snapshot_ids2.tmp && mv $DIR/tmp/snapshot_ids2.tmp $DIR/tmp/snapshot_ids.tmp
      break;
    elif [[ ! -e $DIR/tmp/snapshot_$SNAP_ID.tmp ]];
    then
      continue;
    else
      clear
      echo "Deleting snapshot $SNAP_ID after all are available..."
      echo "Snapshot $SNAP_ID is $(cat $DIR/tmp/snapshot_$SNAP_ID.tmp|grep status|awk '{print $2}'|tr ',' ' ')"
      echo "Snapshot progress: $(cat $DIR/tmp/snapshot_$SNAP_ID.tmp|grep progress|awk '{print $2}'|tr ',' ' ')"
      sleep 3 
      statusSnapshots
      continue;
    fi
    done 
    # delete last snapshot in snapshot ids
    curl "https://$DATACENTER.blockstorage.api.rackspacecloud.com/v1/$TENANT_ID/snapshots/$(tail -n$id $DIR/tmp/snapshot_ids.tmp)" \
    -X DELETE \
    -H "X-Auth-Token: $TOKEN"
    sed "/"$SNAP_ID"/d" $DIR/tmp/snapshot_ids.tmp > $DIR/tmp/snapshot_ids2.tmp 
    mv $DIR/tmp/snapshot_ids2.tmp $DIR/tmp/snapshot_ids.tmp
  continue;
  done
}

SNAP_NUM=$(cat $DIR/tmp/snapshot_ids.tmp|wc -l)

if [[ $(cat $DIR/tmp/snapshot_ids.tmp) == "" ]];
  then
  echo "No created snapshots"
  # statusSnapshots
  createSnapshots
  statusSnapshots
  else
    echo "Snapshot IDs not empty"
    # deleteSnapshots
fi

if [[ $SNAP_NUM == $SNAP_RET ]];
then
  clear
  echo "$SNAP_NUM snapshots have been created"
  echo "Deleting snapshot..."
  # echo "$(cat $DIR/tmp/snapshot_ids.tmp)"
  sleep 3
  deleteSnapshots
  statusSnapshots
  createSnapshots
  statusSnapshots

elif [[ $SNAP_NUM < $SNAP_RET  ]];
then  
  clear
  echo "Creating snapshot"
  sleep 3
  createSnapshots
  statusSnapshots

elif [[ $SNAP_NUM > $RET_NUM ]];
then
  echo "Snapshot number creater than retention number"
  echo "Deleting last snapshot..."
  deleteSnapshots
  statusSnapshots
fi

if [[ ! -e $DIR/tmp/snapshots_created.tmp.gz  ]];
then
        gzip -f $DIR/tmp/snapshots_created.tmp;
fi

#!/bin/bash
DDI=""
TOKEN=""
APIKEY=""
SUBDOMAIN=""
TYPE=""
HOST=""
# change to YES to automatically run import operation
IMPORT="YES"
ID=""
DIR=/root/dns
# change to yes to check each record via curl, very slow
VERIFY="YES"

usage()
{
cat << EOF
usage: $0 options

This script makes it easy to add a domain in bulk

OPTIONS:
   -h      Show this message
   -a      api key (cloud) 
   -u      username (cloud)
   -d      host (ip/domain)
   -s      subdomain
   -r      record type

EXAMPLE: ./add_subdomain.sh -a 1234567 -u herpderp -d 127.0.0.1 -s www1 -r A
EOF
}

while getopts “h:a:u:d:s:r:” OPTION
do
     case "$OPTION" in
         h)
             usage
             exit 1
             ;;
         a)
             if [[ "$APIKEY" == "" ]]
             then
               APIKEY="$OPTARG"
             fi
             ;;

         u) 
             if [[ "$USERNAME" == "" ]]
             then
               USERNAME="$OPTARG"
             fi
             ;;
         d) 
             if [[ "$HOST" == "" ]]
             then
	       HOST="$OPTARG"
	     fi
             ;; 

         s)
             if [[ "$SUBDOMAIN" == "" ]]
             then
               SUBDOMAIN="$OPTARG"
             fi
	     ;;
         r)
             if [[ "$TYPE" == "" ]]
             then
               TYPE="$OPTARG"
	     fi
             ;;
         ?)
             usage
             ;;
     esac
done

if [[ -z "$USERNAME" ]] || [[ -z "$APIKEY" ]] || [[ -z "$HOST" ]] || [[ -z "$SUBDOMAIN" ]] || [[ -z "$TYPE" ]]
then
     usage
printf "
API: $APIKEY
DDI: $DDI  
TOKEN: $TOKEN  
HOST: $HOST  
SUBDOMAIN: $SUBDOMAIN 
RECORD:  $TYPE

"
exit 
fi


# do not add to existing data
rm -fr $DIR/verify.sh
rm -fr $DIR/import.sh
touch $DIR/import.sh
touch $DIR/verify.sh
rm -fr $DIR/tmp
mkdir $DIR/tmp
mkdir $DIR/tmp/verify
touch $DIR/tmp/verify/existing.txt
touch $DIR/tmp/zones.txt
touch $DIR/tmp/ids.txt
touch $DIR/tmp/names.txt
touch $DIR/tmp/domains.txt
touch $DIR/tmp/existing.txt
touch $DIR/tmp/import.json
touch $DIR/tmp/subdomains.txt

# acquire token

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
DDI="$(grep tenant tmp/auth.txt|uniq|head -n1|awk '{print $2}'|tr '"' ' '|awk '{print $1}')"
TOKEN="$(cat $DIR/tmp/token.txt)"

printf "If something goes wrong, check output of last command in $DIR/tmp/zones.txt.\n\n"
printf "Getting list of domains...\n\n"
# acquire each zone
curl -s https://dns.api.rackspacecloud.com/v1.0/$DDI/domains \
  -H "X-Auth-Token: $TOKEN" | python -m json.tool > $DIR/tmp/zones.txt
sleep 1

if [[ $(grep "code" $DIR/tmp/zones.txt) == *"401"* ]]
then
  printf "Code 401. Renew auth token\n\n"
  exit 1
fi

# filter out name and ids
printf "Filtering out names and ids in ids.txt and names.txt... \n\n"
while read zones
do
  echo $zones|grep id|awk '{print $2}'|tr ',' ' ' >> $DIR/tmp/ids.txt
  echo $zones|grep name|awk '{print $2}'|cut -d '"' -f2 >> $DIR/tmp/names.txt 
done < $DIR/tmp/zones.txt

printf "$(awk '{print $1}' $DIR/tmp/ids.txt > $DIR/tmp/tmp.txt && mv $DIR/tmp/tmp.txt $DIR/tmp/ids.txt)"
ID="$(head -n1 $DIR/tmp/ids.txt)"

# append subdomain to domain
printf "Adding subdomain to domain in domains.txt...\n\n"
while read domains
do 
if [[ $SUBDOMAIN != "" ]]
then
  printf "$domains \n" >> "$DIR/tmp/domains.txt"
  domain="$SUBDOMAIN.$domains"
  printf "$domain\n" >> "$DIR/tmp/subdomains.txt" 
fi
done < $DIR/tmp/names.txt
clear 

printf "Checking for matching records...\n\n" 

sleep 4

while read domains
do
  # compare only domains that return true for match
  MATCH="$(dig $domains $TYPE|grep ANSWER -A1|grep $domains|grep [0-9])\n"
  if [[ $MATCH != "" ]]
  then
    printf "$MATCH \n" >> $DIR/tmp/existing.txt
  fi
done < $DIR/tmp/subdomains.txt

# remove extra spaces
sed -i -e '/^ *$/d' $DIR/tmp/existing.txt

printf "The following domains are already responding with an $TYPE record, skipping: \n\n"
printf "$(cat $DIR/tmp/existing.txt)\n"

sleep 4

# this attempts to verify each record listed,
# this does take some time
if [[ "$VERIFY" == "YES" ]]
then
  printf "\nVerifying subdomain records in account...\n\n"
  while read subdomains <&3 && read ids <&4
  do
     printf "#!/bin/bash \n
touch \"$DIR/tmp/verify/$subdomains.status\" \nwhile [[ \"\$(grep \"records\" $DIR/tmp/verify/$subdomains.status)\" != *\"records\"* ]]
do
TOKEN=\"\$(cat $DIR/tmp/token.txt)\" \n
  curl -s -H \"X-Auth-Token: \$TOKEN\" -H \"Content-Type: application/json\" \"https://dns.api.rackspacecloud.com/v1.0/$DDI/domains/$ids/records\"|python -mjson.tool >> \"$DIR/tmp/verify/$subdomains.status\"

tail -n10 \"$DIR/tmp/verify/$subdomains.status\"

sleep 2
done
printf \"\$(grep $subdomains $DIR/tmp/verify/$subdomains.status -B2|egrep name\|data|tac)\\\\n\\\\n\" >> \"$DIR/tmp/verify/existing.txt\"

printf \"\$(grep $subdomains $DIR/tmp/verify/$subdomains.status -B2|egrep name\|data|tac)\\\\n\\\\n\"

mv $DIR/tmp/verify/$subdomains.sh $DIR/tmp/verify/subdomains

" > "$DIR/tmp/verify/$subdomains.sh"

  done 3<"$DIR/tmp/subdomains.txt" 4<"$DIR/tmp/ids.txt"

  printf "$(chmod +x $DIR/verify.sh)"
  printf "#!/bin/bash
  for subdomains in $DIR/tmp/verify/*.sh
do
  printf \"Running \$subdomains... \\\\n\"
  printf \"\$(bash \$subdomains) \\\\n\\\\n\"

done \n


" >> $DIR/verify.sh 
bash $DIR/verify.sh

printf "$(awk '{print $2}' $DIR/tmp/verify/existing.txt > $DIR/tmp/verify/tmp.txt)"

# remove extra spaces
sed -i -e '/^ *$/d' $DIR/tmp/verify/existing.txt
printf "\n" >> $DIR/tmp/existing.txt

# no duplicate records
printf "Listed in account: \n" >> "$(cat $DIR/tmp/verify/existing.txt)"
printf "$(cat $DIR/tmp/verify/existing.txt) \n" >> $DIR/tmp/existing.txt


fi

printf "\n" >> $DIR/tmp/existing.txt

# remove unnecessary "." at the end from dig
printf "$(rev $DIR/tmp/existing.txt|cut -c 2-|rev > $DIR/tmp/tmp.txt && mv $DIR/tmp/tmp.txt $DIR/tmp/existing.txt)"

clear 

printf "The following records already have $SUBDOMAIN listed as a subdomain (skipping): \n\n"
printf "$(cat $DIR/tmp/verify/existing.txt)" >> "$DIR/tmp/existing.txt"
printf "$(cat $DIR/tmp/existing.txt)\n"
sleep 2 

while read subdomains <&3 && read ids <&4 
do
  MATCH="$(grep $subdomains $DIR/tmp/existing.txt)"
  if [[ $MATCH == "" ]]
  then
  # grab each name and id and iterate as two seperate variables
  # add to seperate domain list, including subdomain to verify
  # this SERIOUSLY needs to be refactored at some point

  printf "#!/bin/bash \n 
touch \"$DIR/tmp/$subdomains.status\" \nwhile [[ \"\$(grep \"RUNNING\" $DIR/tmp/$subdomains.status)\" != *\"RUNNING\"* ]]
do
TOKEN=\"\$(cat $DIR/tmp/token.txt)\" \n

  curl -s -d \
    \"{
    \\\\\"records\\\\\": [
        {
        \\\\\"name\\\\\" : \\\\\"$subdomains\\\\\",
        \\\\\"type\\\\\" : \\\\\"$TYPE\\\\\",
        \\\\\"data\\\\\" : \\\\\"$HOST\\\\\",
        \\\\\"ttl\\\\\" : 3600
        } \
      ]
     }\" -H \"X-Auth-Token: \$TOKEN\" -H \"Content-Type: application/json\" \"https://dns.api.rackspacecloud.com/v1.0/$DDI/domains/$ids/records\"|tee \"$DIR/tmp/$subdomains.status\"
  
    printf \"\$(cat $DIR/tmp/$subdomains.status)\"

sleep 2 
done 

  
mv $DIR/tmp/$subdomains.sh $DIR/tmp/subdomains
" >> "$DIR/tmp/$subdomains.sh"
  fi

done  3<$DIR/tmp/subdomains.txt 4<$DIR/tmp/ids.txt

# record name, type, IP
# printf "$(awk '{print $1,$4,$5}' $DIR/tmp/existing.txt > $DIR/tmp/tmp.txt && mv -f $DIR/tmp/tmp.txt $DIR/tmp/existing.txt)"

# remove extra spaces
sed -i -e '/^ *$/d' $DIR/tmp/existing.txt
printf "\n" >> $DIR/tmp/existing
# remove unnecessary "." at the end from dig
printf "$(rev $DIR/tmp/existing.txt|cut -c 2-|rev > $DIR/tmp/tmp.txt && mv $DIR/tmp/tmp.txt $DIR/tmp/existing.txt)"

# import.sh is created to substitue tokens for all subdomains
# in event that token expires and subdomains still need to be
# added 

printf "$(chmod +x $DIR/import.sh)"
printf "#!/bin/bash 
if [[ \$(ls /root/dns/tmp|grep .sh) != \"\" ]]
then
  for subdomains in $DIR/tmp/*.sh
  do
    printf \"Running \$subdomains... \\\\n\"
    printf \"\$(bash -x \$subdomains) \\\\n\\\\n\"
  done 
else
  printf \"Subdomain exists in all domains.\\\\n\"
fi

\n" >> $DIR/import.sh

if [[ $IMPORT == "YES" ]]
then
  bash $DIR/import.sh
else
  printf "\nAlmost done. Run bash import.sh to run import operation.\n\n"
fi


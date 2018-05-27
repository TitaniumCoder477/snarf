#!/bin/bash
#
# snarf.sh 
# 
# This script reads a domain and calls docker run elceef/dnstwist on the domain.
# It then pipes the results into a file, after which it reads the file and uses
# cutycapt to create a picture folder with screenshots of the websites it found.
#
# Requires: Fully functional docker and cutycapt (which also requires X)
# Optional: If you are running on a headless server, make sure to install xvfb
#           because cutycapt won't run without at least a dummy X.
#
# MIT License
# 
# Copyright (c) 2018 James Robert Wilmoth
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
#	./snarf.sh google.com
#	./snarf.sh fileofdomains.lst
#

##############################################################
#Make sure we have all the requirements
printf "Checking for availability of requirements...\n"
docker > /dev/null 2>&1
if [[ $? -eq 127 ]]; then
	printf "> !! docker does not exist. Please install first. Aborting...\n"
	exit $?
fi

cutycapt > /dev/null 2>&1
if [[ $? -eq 127 ]]; then
	printf "> !! cutycapt does not exist. Please install first. Aborting...\n"
	exit $?
fi

XPID=-1
if [[ -z "${DISPLAY}" ]]; then
	printf "> !! X not available. Testing for availability of Xvfb...\n"
	xvfb-run > /dev/null 2>&1
	if [[ $? -eq 127 ]]; then
		printf "> !! X not available and Xvfb not available. Please either ssh -X to this machine, or install xvfb or X. Aborting...\n"
		exit $?
	else
		printf "> xvfb is installed. Started virtual X server on display 0...\n"
		Xvfb :0 -auth /tmp/xvfb.auth -ac -screen 0 1920x1080x24 &
		XPID=$!
		export DISPLAY=:0
	fi
fi
printf "...X is ready for use.\n"

PARAMETER="$1"

DOMAINS=()

##############################################################
#Loop through file
if [ -f "$PARAMETER" ]; then

	DOMAINLIST="$PARAMETER"

	printf "Reading domains from file...\n"
	while IFS= read -r DOMAIN; do
		printf "> Read $DOMAIN...\n"
		DOMAINS+=("$DOMAIN")
	done < "$DOMAINLIST"	

#Or accept domain as argument
elif [[ $PARAMETER =~ (([a-zA-Z](-?[a-zA-Z0-9])*)\.)*[a-zA-Z](-?[a-zA-Z0-9])+\.[a-zA-Z]{2,} ]]; then 

	DOMAINS+=("$PARAMETER")

#Or return an error
else
	echo "You must not have entered a valid file or file!"
	echo "Synax: ./snarf.sh fileofdomains.lst   OR   ./snarf.sh google.com"
	echo.
	exit 1
fi

#Success - proceed to logic code

##############################################################
printf "Starting docker container(s)...\n"	
i=0; PIDS=;
for DOMAIN in "${DOMAINS[@]}"; do

	SOURCE="./$DOMAIN.lst"
	FOLDER="$DOMAIN"
	
	mkdir "$FOLDER" > /dev/null 2>&1
	
	printf "> Starting a docker container for dnstwist on $DOMAIN...\n"
	#Output results (even if domain is resolvable)
	docker run elceef/dnstwist "$DOMAIN" > "$SOURCE" &
	PIDS[$((i++))]=$!
	
done
printf "...waiting for docker container(s) to finish\n"
for PID in ${PIDS[*]}; do
	wait $PID
done

##############################################################
printf "Running cutycap on result(s) to generate website preview images and creating html index page(s)...\n"
i=0; PIDS=;
for DOMAIN in "${DOMAINS[@]}"; do

	CONTENT_HEADER="
		<!DOCTYPE html>
		<html>
		<head>
		<style>
		div.gallery {
			margin: 5px;
			border: 1px solid #ccc;
			float: left;
			width: 180px;
		}

		div.gallery:hover {
			border: 1px solid #777;
		}

		div.gallery img {
			width: 100%;
			height: auto;
		}

		div.desc {
			padding: 15px;
			text-align: center;
		}
		</style>
		</head>
		<body>
		<h1>Here are the results for $DOMAIN</h1>
		<p>Thumbnails open in a new tab.</p>
	"

	CONTENT_BODY_SEGMENTS=()

	SOURCE="./$DOMAIN.lst"
	FOLDER="$DOMAIN"

	printf "> Reading $SOURCE...\n"
	while IFS= read -r line; do
		domain=`echo $line | awk '{print $2}'`
		ip=`echo $line | awk '{print $3}'`
		#Make sure we have an actual IP to cutycap
		if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
			fn="./$FOLDER/$domain-$ip.jpg"
			printf "> cutycapt --url=http://$domain --out=$fn\n"
			cutycapt --url="http://$domain" --out="$fn" &
			PIDS[$((i++))]=$!

			CONTENT_BODY_SEGMENT="
				<div class='gallery'>
				  <a target='_blank' href='$fn'>
					<img src='$fn' alt='' width='300' height='200'>
				  </a>
				  <div class='desc'>$domain</div>
				</div>
			"
			CONTENT_BODY_SEGMENTS+=("$CONTENT_BODY_SEGMENT")
		fi	
	done < "$SOURCE"
	#done < <(tail -n "+9" $SOURCE)
	
	CONTENT_FOOTER="
		</body>
		</html>
	"
	
	#Create the index file
	indexfn="./$DOMAIN.htm"
	echo "$CONTENT_HEADER" >> "$indexfn"	
	for CONTENT_BODY_SEGMENT in "${CONTENT_BODY_SEGMENTS[@]}"; do
		echo "$CONTENT_BODY_SEGMENT" >> "$indexfn"
	done	
	echo "$CONTENT_FOOTER" >> "$indexfn"

done
printf "...waiting for cutycap process(es) to finish. Ignore any cutycap errors. Wait for done message.\n"
for PID in ${PIDS[*]}; do
	wait $PID
done

#If we created a xvfb process, make sure we remove it
ps -p $XPID > /dev/null 2>&1
if [[ $? -eq 0 ]]; then
	kill $XPID > /dev/null 2>&1
fi

##############################################################
printf "Done!\n"

exit 0
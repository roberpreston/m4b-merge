#!/bin/bash
# Script to use m4b-tool to merge audiobooks, easily.

#LOCAL FOLDERS
INPUT="/home/$USER/incoming/audiobooks"
TOMOVE="/home/$USER/Downloads/audiobooks/SORTING"
OUTPUT="/mnt/disk1/audiobooks"

M4BPATH="/home/$USER/m4b-tool/m4b-tool.phar"
METADATA="/home/$USER/m4b-tool"

# Common config, shared between multiple scripts
COMMONCONF="/home/$USER/.config/scripts/common.cfg"


# -h help text to print
usage="	$(basename "$0") $VER [-b] [-h] [-n]

	'-b' Batch mode.
	'-h' This help text.
	'-n' Enable Pushover notifications.
	"

# Flags for this script
	while getopts ":bhn" option; do
 case "${option}" in
	b) BATCHMODE=true
		;;
	h) echo "$usage"
 		exit
		;;
	n) PUSHOVER=true
		;;
 \?) echo -e "\e[91mInvalid flag: -"$OPTARG". Use '-h' for help.\e[0m" >&2
 	;;
 :) echo -e "\e[91mOption -$OPTARG requires a value.\e[0m" >&2
      exit 1
	;;

 esac
done

### Functions ###

function collectmeta() {
	IFS=$'\n'
	select adbook in $(cat $INPUT/.abook) exit; do
	  case "$adbook" in
	      exit) echo "exiting"
	            break ;;
	         *) read -e -p 'Enter name: ' namevar
			 	read -e -p 'Enter Albumname: ' albumvar
			 	read -e -p 'Enter artist (Narrator): ' artistvar
			 	read -e -p 'Enter albumartist (Author): ' albumartistvar
				read -e -p 'Enter bitrate, if any: ' brvar
				read -e -p 'Enter Musicbrainz ID, if any: ' mbrainid
				if [[ singleuse == "true" ]]; then
					if [[ -z $brvar ]]; then
						brvar=""
					else
						brvar="--audio-bitrate=$brvar"
					fi
					if [[ -z $mbrainid ]]; then
						mbrainid=""
					else
						mbrainid="--musicbrainz-id=$mbrainid"
					fi
			 		echo "Starting conversion of $adbook"
			 		mkdir -p "$TOMOVE"/"$albumartistvar"/"$albumvar"
					php "$M4BPATH" merge "$INPUT"/"$adbook" --output-file="$TOMOVE"/"$albumartistvar"/"$albumvar"/"$namevar".m4b --name="$namevar" --album="$albumvar" --artist="$artistvar" --albumartist="$albumartistvar" "$brvar" "$mbrainid" --ffmpeg-threads=2 | pv -p -t -l -N "Merging $namevar" > /dev/null
					rm -rf "$TOMOVE"/"$albumartistvar"/"$albumvar"/*-tmpfiles
					echo "Merge has finished."
					echo "Previous folder size: $(du -hcs "$INPUT"/"$adbook" | cut -f 1 | tail -n1)"
					echo "New folder size: $(du -hcs "$TOMOVE"/"$albumartistvar"/"$albumvar" | cut -f 1 | tail -n1)"
					read -e -p 'Delete source folder? y/n ' delvar
					if [[ $delvar = "y" ]]; then
						rm -rf "$INPUT"/"$adbook"
					fi
				else
					adbookx="$(basename "$adbook")"
					adbook2="${adbookx//[^[:alnum:]]/}"
					echo "exists=true" > "$METADATA"/."$adbook2".txt
					echo "namevar='$namevar'" >> "$METADATA"/."$adbook2".txt
					echo "albumvar='$albumvar'" >> "$METADATA"/."$adbook2".txt
					echo "artistvar='$artistvar'" >> "$METADATA"/."$adbook2".txt
					echo "albumartistvar='$albumartistvar'" >> "$METADATA"/."$adbook2".txt
					if [[ -z $brvar ]]; then
						brvar=""
					else
						brvar="--audio-bitrate='$brvar'"
						echo "brvar='$brvar'" >> "$METADATA"/."$adbook2".txt
					fi
					if [[ -z $mbrainid ]]; then
						mbrainid=""
					else
						mbrainid="--musicbrainz-id=$mbrainid"
						echo "mbrainid='$mbrainid'" >> "$METADATA"/."$adbook2".txt
					fi
				fi
				;;
	  esac
	done
}

function batchprocess() {
if [[ $BATCHMODE == "true" ]]; then
	for dir in "$INPUT"/*
	do
		dirx="$(basename "$dir")"
		dir2="${dirx//[^[:alnum:]]/}"
		if [[ -f $METADATA/.$dir2.txt ]]; then
			source $METADATA/.$dir2.txt
			echo "Starting conversion of $(basename "$dir")"
			mkdir -p "$TOMOVE"/"$albumartistvar"/"$albumvar"
			php "$M4BPATH" merge "$dir" --output-file="$TOMOVE"/"$albumartistvar"/"$albumvar"/"$namevar".m4b --name="$namevar" --album="$albumvar" --artist="$artistvar" --albumartist="$albumartistvar" "$brvar" "$mbrainid" --ffmpeg-threads=2 | pv -p -t -l -N "Merging "$namevar"" > /dev/null
			rm -rf "$TOMOVE"/"$albumartistvar"/"$albumvar"/*-tmpfiles
			echo "Merge has finished."
			echo "old='Previous folder size: $(du -hcs "$dir" | cut -f 1 | tail -n1)'" >> "$METADATA"/."$dir2".txt
			echo "new='New folder size: $(du -hcs "$TOMOVE"/"$albumartistvar"/"$albumvar" | cut -f 1 | tail -n1)'" >> "$METADATA"/."$dir2".txt
			echo "del='ready'" >> "$METADATA"/."$dir2".txt
			unset namevar albumvar artistvar albumartistvar old new del
		fi
	done
fi
}

function batchprocess2() {
if [[ $BATCHMODE == "true" ]]; then
	echo "Let's go over the folders that have been processed:"
	for dir in "$INPUT"/*
	do
		dirx="$(basename "$dir")"
		dir2="${dirx//[^[:alnum:]]/}"
		if [ ! -d "SORTING"/* ]; then
			if [[ -s $METADATA/.$dir2.txt ]]; then
				source $METADATA/.$dir2.txt
				if [ "$del" = ready ]; then
					echo "Checking $dir ..."
					echo "Previous folder size: $old"
					echo "New folder size: $new"
					read -e -p 'So should this source be deleted? y/n: ' delvar
					if [[ $delvar = "y" ]]; then
						echo "rm -rf "$dir"" >> "$DELTRUE"
						rm "$METADATA"/."$dir2".txt
					fi
				fi
			fi
		fi
	done

	echo "Ok, now deleting folders you confirmed..."

	bash "$DELTRUE"
fi
}

function pushovr() {
	# Check if user wanted notifications
	if [ "$PUSHOVER" = "true" ]; then
		echo "Sending Pushover notification..."
		MESSAGE="m4b-merge script has finished."
		TITLE="m4b-merge finished"
		source "$COMMONCONF"
		curl -s \
	    -F "token=$APP_TOKEN" \
	    -F "user=$USER_TOKEN" \
	    -F "title=$TITLE" \
	    -F "message=$MESSAGE" \
	    https://api.pushover.net/1/messages.json
		echo "Script finished."
	fi
}

### End functions ###

echo "Getting folder/files to use..."

if [ -s "$INPUT"/.abook ]; then
	echo "Error: List of folders was not cleaned properly"
else
	touch "$INPUT"/.abook
	for dir in $INPUT/*
	do
		if [[ $(find "$dir"/* -type f -regex ".*\.\(mp3\|m4b\)" | wc -l) -gt 1 ]]; then
			echo "$(basename "$dir")" >> "$INPUT"/.abook
		fi
	done
fi

# Gather metadata from user
collectmeta
# Process metadata batch
batchprocess
batchprocess2

rm "$INPUT"/.abook

# Send notification
pushovr

#!/bin/bash
# Script to use m4b-tool to merge audiobooks, easily.

#LOCAL FOLDERS
INPUT="/home/$USER/incoming/audiobooks"
TOMOVE="/home/$USER/Downloads/audiobooks/SORTING"
OUTPUT="/mnt/disk1/audiobooks"

M4BPATH="/home/$USER/m4b-tool/m4b-tool.phar"

# Common config, shared between multiple scripts
COMMONCONF="/home/$USER/.config/scripts/common.cfg"


# -h help text to print
usage="	$(basename "$0") $VER [-b] [-f] [-h] [-n]

	'-f' File or folder to run from. Enter multiple files if you need, as: -f file1 -f file2 -f file3
	'-h' This help text.
	'-n' Enable Pushover notifications.
	"

# Flags for this script
	while getopts ":f:hn" option; do
 case "${option}" in
	f) FILEIN+=("$(realpath "$OPTARG")")
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
	#New shits
	for SELDIR in "${FILEIN[@]}"; do
		# Basename of array values
		BASESELDIR="$(basename "$SELDIR")"
		M4BSELFILE="/tmp/.m4bmerge.$BASESELDIR.txt"

		if [[ -f $M4BSELFILE ]]; then
			echo "Metadata for this audiobook exists"
			read -e -p 'Use existing metadata? y/n: ' useoldmeta
			if [[ $useoldmeta == "n" ]]; then
				echo -e "\e[92mEnter metadata for $BASESELDIR\e[0m"
				# Each line has a line after input, adding that value to an array.
				read -e -p 'Enter name: ' m4bvar
				M4BARR+=("--name='$m4bvar';;")
				read -e -p 'Enter Albumname: ' m4bvar
				M4BARR+=("--album='$m4bvar';;")
				read -e -p 'Enter artist (Narrator): ' m4bvar
				M4BARR+=("--artist='$m4bvar';;")
				read -e -p 'Enter albumartist (Author): ' m4bvar
				M4BARR+=("--albumartist='$m4bvar';;")
				read -e -p 'Enter bitrate, if any: ' -i "--audio-bitrate=" m4bvar
				M4BARR+=("$m4bvar")
				read -e -p 'Enter Musicbrainz ID, if any: ' -i "--musicbrainz-id=" m4bvar
				M4BARR+=("$m4bvar")

				# Make array into file
				echo "${M4BARR[*]}" > "$M4BSELFILE"
				# First make the directory destination for audiobook.
				mkdir -p "$TOMOVE"/"$BASESELDIR"
			fi
		fi
	done
}

function batchprocess() {
	for SELDIR in "${FILEIN[@]}"; do
		# Basename of array values
		BASESELDIR="$(basename "$SELDIR")"
		M4BSELFILE="/tmp/.m4bmerge.$BASESELDIR.txt"

		readarray M4BSEL <<<"$(tr ';;' '\n'<<<"$(cat "$M4BSELFILE")")"
		albumartistvar="$(echo "${#M4BSEL[6]}" | cut -f 2 -d '=')"
		albumvar="$(echo "${#M4BSEL[2]}" | cut -f 2 -d '=')"
		namevar="$(echo "${#M4BSEL[0]}" | cut -f 2 -d '=')"

		echo "Starting conversion of $(basename "$SELDIR")"
		mkdir -p "$TOMOVE"/"$albumartistvar"/"$albumvar"
		php "$M4BPATH" merge "$SELDIR" --output-file="$TOMOVE"/"$albumartistvar"/"$albumvar"/"$namevar".m4b "${M4BSEL[*]}" --ffmpeg-threads=8 | pv -p -t -l -N "Merging $namevar" > /dev/null
		#rm -rf "$TOMOVE"/"$albumartistvar"/"$albumvar"/*-tmpfiles
		echo "Merge has finished."
		#echo "old='Previous folder size: $(du -hcs "$SELDIR" | cut -f 1 | tail -n1)'" >> "$METADATA"/."$dir2".txt
		#echo "new='New folder size: $(du -hcs "$TOMOVE"/"$albumartistvar"/"$albumvar" | cut -f 1 | tail -n1)'" >> "$METADATA"/."$dir2".txt
		#echo "del='ready'" >> "$METADATA"/."$dir2".txt
		#unset namevar albumvar artistvar albumartistvar old new del
	done
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
		MESSAGE="m4b-merge script has finished processing all specified audiobooks. Waiting on user to tell me what to delete."
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

# Small one time check for 'pv'
if [[ ! -f "$(dirname "$M4BPATH")"/.pv.lock ]]; then
	if [[ $(which pv) == "" ]]; then
		echo "The program for progress bar is missing."
		read -e -p 'Install it now? y/n: ' pvvar
		if [[ $pvvar == "y" ]]; then
			sudo apt-get install pv
		fi
		touch "$(dirname "$M4BPATH")"/.pv.lock
	fi
fi

# Gather metadata from user
collectmeta
# Process metadata batch
batchprocess
# Send notification
pushovr

#echo "Starting rclone background move"
#exec screen -dmS rclonem4b rclone move "$TOMOVE" "$OUTPUT" --transfers=1 --verbose --stats 15s

batchprocess2

echo "Script complete."

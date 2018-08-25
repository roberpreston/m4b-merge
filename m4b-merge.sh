#!/bin/bash
# Script to use m4b-tool to merge audiobooks, easily.

#LOCAL FOLDERS
INPUT="/home/$USER/incoming/audiobooks"
TOMOVE="/home/$USER/Downloads/audiobooks/SORTING"
OUTPUT="/mnt/hdd/audiobooks"

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

function preprocess() {
	# Let's first check that the input folder, actually should be merged.
	for SELDIR in "${FILEIN[@]}"; do
		FINDCMD="$(find "$SELDIR" -type f -iname ".$EXT" | wc -c)"
		EXT="m4b"
		if [[ $FINDCMD -gt 0 && $FINDCMD -le 2 ]]; then
			echo "We only found $FINDCMD $EXT files in $SELDIR. It is not recommended to merge so few files"
			exit 1
		fi
		EXT="mp3"
		if [[ $FINDCMD -gt 0 && $FINDCMD -le 2 ]]; then
			echo "We only found $FINDCMD $EXT files in $SELDIR. It is not recommended to merge so few files"
			exit 1
		fi
	done
}

function collectmeta() {
	#New shits
	for SELDIR in "${FILEIN[@]}"; do
		# Basename of array values
		BASESELDIR="$(basename "$SELDIR")"
		M4BSELFILE="/tmp/.m4bmerge.$BASESELDIR.txt"

		# Check if we can use an existing metadata entry
		if [[ -f $M4BSELFILE ]]; then
			echo "Metadata for this audiobook exists"
			read -e -p 'Use existing metadata? y/n: ' useoldmeta
		fi

		# Create new metadata file
		if [[ $useoldmeta != "y" ]]; then
			echo -e "\e[92mEnter metadata for $BASESELDIR\e[0m"
			# Each line has a line after input, adding that value to an array.
			read -e -p 'Enter name: ' m4bvar1
			read -e -p 'Enter Albumname: ' m4bvar2
			read -e -p 'Enter artist (Narrator): ' m4bvar3
			read -e -p 'Enter albumartist (Author): ' m4bvar4
			read -e -p 'Enter bitrate, if any (leave blank for none): ' m4bvar5
			read -e -p 'Enter Musicbrainz ID, if any (leave blank for none): ' m4bvar6

			# Check if we need to include optional arguments in the array
			if [[ -z $m4bvar5 ]]; then
				bitrate=""
			else
				bitrate="--musicbrainz-id='$m4bvar5'"
			fi
			if [[ -z $m4bvar6 ]]; then
				mbid=""
			else
				mbid="--musicbrainz-id='$m4bvar6'"
			fi

			# Put all values into an array
			M4BARR+=(
			"--name='${m4bvar1// /_}'"
			"--album='${m4bvar2// /_}'"
			"--artist='${m4bvar3// /_}'"
			"--albumartist='${m4bvar4// /_}'"
			"$bitrate"
			"$mbid"
			)

			# Make array into file
			echo "${M4BARR[*]}" > "$M4BSELFILE"
			# First make the directory destination for audiobook.
			mkdir -p "$TOMOVE"/"$BASESELDIR"
		fi
	done
}

function batchprocess() {
	INPUTNUM="${#FILEIN[@]}"
	# Output number of folders to process
	echo "Let's begin processing input folders"
	echo "Number of folders to process: $INPUTNUM"

	for ((i=0; i < INPUTNUM; i++)); do
		j=$((i+1))
		#echo  "($j of $INPUTNUM): Processing ${FILEIN[$i]}"
		for SELDIR in "${FILEIN[@]}"; do
			# Basename of array values
			BASESELDIR="$(basename "$SELDIR")"
			M4BSELFILE="/tmp/.m4bmerge.$BASESELDIR.txt"

			# Import values from file into array.
			readarray M4BSEL <<<"$(cat "$M4BSELFILE" | tr ' ' '\n' | tr '_' ' ')" #"$(tr ' ' '\n'<<<"$(cat "$M4BSELFILE")")"
			namevar="$(echo "${M4BSEL[0]}" | cut -f 2 -d '=' | sed s/\'//g)"
			albumvar="$(echo "${M4BSEL[1]}" | cut -f 2 -d '=' | sed s/\'//g)"
			albumartistvar="$(echo "${M4BSEL[3]}" | cut -f 2 -d '=' | sed s/\'//g)"

			if [[ -s $M4BSELFILE ]]; then
				#echo "Starting conversion of "$namevar""
				mkdir -p "$TOMOVE"/"$albumartistvar"/"$albumvar"
				echo  "($j of $INPUTNUM): Processing $albumvar..."
				php "$M4BPATH" merge "$SELDIR" --output-file="$TOMOVE"/"$albumartistvar"/"$albumvar"/"$namevar".m4b "${M4BSEL[*]}" --mark-tracks -q --ffmpeg-threads="$(grep -c ^processor /proc/cpuinfo)" #| pv -l -p -t -N "Merging $albumvar" > /dev/null
				echo "Merge has finished for "$namevar"."
				rm -rf "$TOMOVE"/"$albumartistvar"/"$albumvar"/*-tmpfiles

				# Make sure output file exists as expected
				if [[ -s $TOMOVE/$albumartistvar/$albumvar/$namevar.m4b ]]; then
					METADATA="/tmp/.m4bmeta.$BASESELDIR.txt"
					echo "old='Previous folder size: $(du -hcs "$SELDIR" | cut -f 1 | tail -n1)'" > "$METADATA"
					echo "new='New folder size: $(du -hcs "$TOMOVE"/"$albumartistvar"/"$albumvar" | cut -f 1 | tail -n1)'" >> "$METADATA"
					echo "del='ready'" >> "$METADATA"
					unset namevar albumvar artistvar albumartistvar old new del
				else
					exit 1
				fi
			else
				echo "Error: metadata file does not exist"
				exit 1
			fi
		done
done
}

function batchprocess2() {
	echo "Let's go over the folders that have been processed:"
	for SELDIR in "${FILEIN[@]}"; do
		METADATA="/tmp/.m4bmeta.$BASESELDIR.txt"

		# Make sure metadata file exists before trying to process it.
		if [[ -s $METADATA ]]; then
			source $METADATA
		else
			echo "Error: metadata file not found. exiting..."
			exit 1
		fi

		# Check that this metadata is ready to process, and then display info to user.
		if [ "$del" = ready ]; then
			echo "Checking $SELDIR ..."
			echo "Previous folder size: $old"
			echo "New folder size: $new"
			read -e -p 'Should this source be deleted? y/n: ' delvar
			if [[ $delvar == "y" ]]; then
				echo "rm -rf "$dir"" >> "$DELTRUE"
				rm "$METADATA"
			fi
		fi
	done

	echo "Ok, now deleting the folders you confirmed..."

	# Process removal commands on source folders.
	for line in "$DELTRUE"; do
		echo "Executing $line"
		$line
	done
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

# Find some information on input FOLDERS
preprocess
# Gather metadata from user
collectmeta
# Process metadata batch
batchprocess
# Send notification
pushovr

echo "Starting rclone background move"
exec screen -dmS rclonem4b rclone move "$TOMOVE" "$OUTPUT" --transfers=1 --verbose --stats 15s

batchprocess2

echo "Script complete."

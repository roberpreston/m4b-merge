#!/bin/bash
# Script to use m4b-tool to merge audiobooks, easily.

#LOCAL FOLDERS
TOMOVE="/home/$USER/Downloads/audiobooks/SORTING"
OUTPUT="/mnt/hdd/audiobooks"

M4BPATH="/home/$USER/m4b-tool/m4b-tool.phar"

# Common config, shared between multiple scripts
COMMONCONF="/home/$USER/.config/scripts/common.cfg"


# -h help text to print
usage="	$(basename "$0") $VER [-b] [-f] [-h] [-n] [-y]

	'-f' File or folder to run from. Enter multiple files if you need, as: -f file1 -f file2 -f file3
	'-h' This help text.
	'-n' Enable Pushover notifications.
	'-y' Answer 'yes' to all prompts.
	"

# Flags for this script
	while getopts ":f:hny" option; do
 case "${option}" in
	f) FILEIN+=("$(realpath "$OPTARG")")
		;;
	h) echo "$usage"
 		exit
		;;
	n) PUSHOVER=true
		;;
	y) YPROMPT=true
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
	# Import metadata into an array, so we can use it.
	importmetadata

	# Common extensions for audiobooks.
	# Check input for each of the above file types, ensuring we are not dealing with a pre-merged input.
	EXT1="$(ls *.m4a 2>/dev/null | wc -l)"
	EXT2="$(ls *.mp3 2>/dev/null | wc -l)"
	EXT3="$(ls *.m4b 2>/dev/null | wc -l)"

	if [[ $EXT1 -gt 1 ]]; then
		EXT="m4a"
	elif [[ $EXT2 -gt 1 ]]; then
		EXT="mp3"
	elif [[ $EXT3 -gt 1 ]]; then
		EXT="m4b"
	fi

	FINDCMD="$(find "$SELDIR" -type f -iname *."$EXT" | wc -c)"
	if [[ $FINDCMD -gt 0 && $FINDCMD -le 2 ]]; then
		echo "NOTICE: only found $FINDCMD $EXT files in $BASESELDIR. Cleaning up file/folder names, but not running merge."
		sfile="true"
		singlefile
	elif [[ -f $SELDIR ]]; then
		sfile="true"
		singlefile
	fi

	if [[ $sfile != "true" ]]; then
		if [[ -d $SELDIR ]]; then
			# After we verify the input needs to be merged, lets run the merge command.
			php "$M4BPATH" merge "$SELDIR" --output-file="$TOMOVE"/"$albumartistvar"/"$albumvar"/"$namevar".m4b "${M4BSEL[@]//$'\n'/}" --force --ffmpeg-threads="$(grep -c ^processor /proc/cpuinfo)" | pv -l -p -t > /dev/null
			echo "Merge completed for $namevar."
		fi
	fi
}

function singlefile() {
	if [[ $sfile == "true" ]]; then
		if [[ -f $SELDIR ]]; then
			mv "$(dirname "$SELDIR")"/"$BASESELDIR" "$TOMOVE"/"$albumartistvar"/"$albumvar"/"$namevar"."$EXT" --verbose
		fi
	elif [[ -d $SELDIR ]]; then
		mv "$(dirname "$SELDIR")"/"$BASESELDIR"/*.$EXT "$TOMOVE"/"$albumartistvar"/"$albumvar"/"$namevar"."$EXT" --verbose
	fi
	echo "Processed single input file for $namevar."
}

function collectmeta() {
	#New shits
	for SELDIR in "${FILEIN[@]}"; do
		# Basename of array values
		BASESELDIR="$(basename "$SELDIR")"
		M4BSELFILE="/tmp/.m4bmerge.$BASESELDIR.txt"

		if [[ $YPROMPT == "true" ]]; then
			useoldmeta="y"
		elif [[ -s $M4BSELFILE ]]; then # Check if we can use an existing metadata entry
			echo "Metadata for $BASESELDIR exists"
			read -e -p 'Use existing metadata? y/n: ' useoldmeta
		elif [[ ! -f $M4BSELFILE ]]; then # Check if we can use an existing metadata entry
			useoldmeta="n"
		fi

		if [[ $useoldmeta == "n" ]]; then
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
			M4BARR=(
			"--name"
			"${m4bvar1// /_}"
			"--album"
			"${m4bvar2// /_}"
			"--artist"
			"${m4bvar3// /_}"
			"--albumartist"
			"${m4bvar4// /_}"
			"$bitrate"
			"$mbid"
			)

			# Make array into file
			echo "${M4BARR[*]}" > "$M4BSELFILE"
		elif [[ -s $M4BSELFILE && $useoldmeta == "y" ]]; then
			echo "Using this metadata then:"
			echo "$(cat "$M4BSELFILE" | tr '_' ' ')"
			echo ""
		fi
	done
}

function importmetadata() {
	# Basename of array values
	BASESELDIR="$(basename "$SELDIR")"
	M4BSELFILE="/tmp/.m4bmerge.$BASESELDIR.txt"

	# Import values from file into array.
	readarray M4BSEL <<<"$(cat "$M4BSELFILE" | tr ' ' '\n' | tr '_' ' ')"
	namevar="$(echo "${M4BSEL[1]}" | sed s/\'//g)"
	albumvar="$(echo "${M4BSEL[3]}" | sed s/\'//g)"
	albumartistvar="$(echo "${M4BSEL[7]}" | sed s/\'//g)"
}

function batchprocess() {
	INPUTNUM="${#FILEIN[@]}"
	((COUNTER++))
	# Output number of folders to process
	echo "Let's begin processing input folders"
	echo "Number of folders to process: $INPUTNUM"

	for SELDIR in "${FILEIN[@]}"; do
		# Basename of array values
		BASESELDIR="$(basename "$SELDIR")"
		M4BSELFILE="/tmp/.m4bmerge.$BASESELDIR.txt"

		# Import metadata into an array, so we can use it.
		importmetadata

		if [[ -s $M4BSELFILE ]]; then
			#echo "Starting conversion of "$namevar""
			mkdir -p "$TOMOVE"/"$albumartistvar"/"$albumvar"
			echo  "($COUNTER of $INPUTNUM): Processing $albumvar..."
			# Process input, and determine if we need to run merge, or just cleanup the metadata a bit.
			preprocess
			((COUNTER++))

			# Make sure output file exists as expected
			if [[ -s $TOMOVE/$albumartistvar/$albumvar/$namevar.m4b ]]; then
				METADATA="/tmp/.m4bmeta.$BASESELDIR.txt"
				echo "old='Previous folder size: $(du -hcs "$SELDIR" | cut -f 1 | tail -n1)'" > "$METADATA"
				echo "new='New folder size: $(du -hcs "$TOMOVE"/"$albumartistvar"/"$albumvar" | cut -f 1 | tail -n1)'" >> "$METADATA"
				echo "del='ready'" >> "$METADATA"
				unset namevar albumvar artistvar albumartistvar old new del
				rm -rf "$TOMOVE"/"$albumartistvar"/"$albumvar"/*-tmpfiles
			else
				exit 1
			fi
		else
			echo "Error: metadata file for $SELDIR does not exist"
			exit 1
		fi
	done
}

function batchprocess2() {
	echo "Let's go over the folders that have been processed:"
	for SELDIR in "${FILEIN[@]}"; do
		METADATA="/tmp/.m4bmeta.$BASESELDIR.txt"
		M4BSELFILE="/tmp/.m4bmerge.$BASESELDIR.txt"

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
				echo "rm -rf "$SELDIR"" >> "$DELTRUE"
				rm "$METADATA"
				rm "$M4BSELFILE"
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

# Make sure user gave usable INPUT
if [[ -z $FILEIN ]]; then
	echo "Error: No file inputs given."
	echo "$usage"
	exit 1
fi

# Gather metadata from user
collectmeta
# Process metadata batch
batchprocess
# Send notification
pushovr

echo "Starting rclone background move"
tmux new-session -d -s rclonem4b 'rclone move "$TOMOVE" "$OUTPUT" --transfers=1 --verbose --stats 15s'

#batchprocess2

echo "Script complete."

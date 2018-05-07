#!/bin/bash
# Script to use m4b-tool to merge audiobooks, easily.

INPUT="/home/$USER/Downloads/audiobooks"
TOMOVE="/home/$USER/Downloads/audiobooks/SORTING"
OUTPUT="/mnt/disk1/audiobooks"
M4BPATH="/home/$USER/m4b-tool/m4b-tool.phar"
METADATA="/mnt/user/Music/ToSort/.metadata.txt"
DELTRUE="/mnt/user/Music/ToSort/.del.txt"


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
					php "$M4BPATH" merge "$INPUT"/"$adbook" --output-file="$TOMOVE"/"$albumartistvar"/"$albumvar"/"$namevar".m4b --name=$namevar --album=$albumvar --artist=$artistvar --albumartist=$albumartistvar "$brvar" "$mbrainid" --ffmpeg-threads=2 | pv -p -t -l -N "Merging $namevar" > /dev/null
					rm -rf "$TOMOVE"/"$albumartistvar"/"$albumvar"/*-tmpfiles
					echo "Merge has finished."
					echo "Previous folder size: $(du -hcs "$INPUT"/"$adbook" | cut -f 1 | tail -n1)"
					echo "New folder size: $(du -hcs "$TOMOVE"/"$albumartistvar"/"$albumvar" | cut -f 1 | tail -n1)"
					read -e -p 'Delete source folder? y/n ' delvar
					if [[ $delvar = "y" ]]; then
						rm -rf "$INPUT"/"$adbook"
					fi
				else
					echo "'$adbook'exists=true" >> "$METADATA"
					echo "'$adbook'name=$namevar" >> "$METADATA"
					echo "'$adbook'album=$albumvar" >> "$METADATA"
					echo "'$adbook'artist=$artistvar" >> "$METADATA"
					echo "'$adbook'albumartist=$albumartistvar" >> "$METADATA"
					if [[ -z $brvar ]]; then
						brvar=""
					else
						brvar="--audio-bitrate=$brvar"
						echo "'$adbook'br=$brvar" >> "$METADATA"
					fi
					if [[ -z $mbrainid ]]; then
						mbrainid=""
					else
						mbrainid="--musicbrainz-id=$mbrainid"
						echo "'$adbook'mbrainid=$mbrainid" >> "$METADATA"
					fi
				fi
				;;
	  esac
	done
}

function batchprocess() {
	echo "Let's go over the folders that have been processed:"

	for dir in "$INPUT"/*
	do
		if [[ $dir != "SORTING" ]]; then
			source "$METADATA"
			if [[ "$dir"del = ready ]]; then
				echo "Checking $dir ..."
				echo "Previous folder size: '$dir'old"
				echo "New folder size: '$dir'new"
				read -e -p 'So should this source be deleted? y/n: ' delvar
				if [[ $delvar = "y" ]]; then
					echo "rm -rf '$dir'" >> "$DELTRUE"
					sed -i '/'$dir'exists/d' "$METADATA"
					sed -i '/'$dir'name/d' "$METADATA"
					sed -i '/'$dir'album/d' "$METADATA"
					sed -i '/'$dir'artist/d' "$METADATA"
					sed -i '/'$dir'albumartist/d' "$METADATA"
					sed -i '/'$dir'br/d' "$METADATA"
					sed -i '/'$dir'mbrainid/d' "$METADATA"
					sed -i '/'$dir'del/d' "$METADATA"
					sed -i '/'$dir'new/d' "$METADATA"
					sed -i '/'$dir'old/d' "$METADATA"
				else
					sed -i '/'$dir'exists/d' "$METADATA"
					sed -i '/'$dir'name/d' "$METADATA"
					sed -i '/'$dir'album/d' "$METADATA"
					sed -i '/'$dir'artist/d' "$METADATA"
					sed -i '/'$dir'albumartist/d' "$METADATA"
					sed -i '/'$dir'br/d' "$METADATA"
					sed -i '/'$dir'mbrainid/d' "$METADATA"
				fi
			fi
		fi
	done

	echo "Ok, now deleting folders you confirmed..."

	bash "$DELTRUE"
}

### End functions ###

echo "Getting folder/files to use..."

if [ -s "$INPUT"/.abook ]; then
	echo "Error: List of folders was not cleaned properly"
else
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
if [[ batchmode == "true" ]]; then
	batchprocess
fi

rm "$INPUT"/.abook

echo "Starting rclone background move"
exec screen -dmS rclonesorted rclone move "$TOMOVE" "$OUTPUT" --transfers=1 --verbose --stats 20s
echo "Script complete."
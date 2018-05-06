#!/bin/bash
# Script to use m4b-tool to merge audiobooks, easily.

INPUT="/home/$USER/Downloads/audiobooks"
TOMOVE="/home/$USER/Downloads/audiobooks/SORTING"
OUTPUT="/mnt/disk1/audiobooks"
DFLTSET="--ffmpeg-threads=8 --no-cache"
M4BPATH="/home/$USER/m4b-tool/m4b-tool.phar"

echo "Getting folder/files to use..."

for dir in $INPUT/*
do
	if [[ $(find "$dir"/* -type f -regex ".*\.\(mp3\|m4b\)" | wc -l) -gt 1 ]]; then
		echo "$(basename "$dir")" >> "$INPUT"/.abook
	fi
done

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
		 	echo "Starting conversion of $adbook"
		 	mkdir -p "$TOMOVE"/"$albumartistvar"/"$albumvar"
			while [ 1 ]; do php "$M4BPATH" merge "$INPUT"/"$adbook" --output-file="$TOMOVE"/"$albumartistvar"/"$albumvar"/"$namevar".m4b --name=$namevar --album=$albumvar --artist=$artistvar --albumartist=$albumartistvar --audio-bitrate=$brvar $DFLTSET; sleep 1; done|pv -p -t -l -N "Merging $namevar" > /dev/null
			echo "Checking file sizes"
			echo "Previous folder size: $(du -hcs "$INPUT"/"$adbook" | cut -f 1 | tail -n1)"
			echo "New folder size: $(du -hcs "$TOMOVE"/"$albumartistvar"/"$albumvar" | cut -f 1 | tail -n1)"
			read -e -p 'Delete source folder? y/n ' delvar
			if [[ $delvar = "y" ]]; then
				rm -rf "$INPUT"/"$adbook"
			fi
			;;
  esac
done

rm "$INPUT"/.abook

echo "Starting rclone background move"
exec screen -dmS rclonesorted rclone move "$TOMOVE" "$OUTPUT" --transfers=1 --verbose --stats 20s
echo "Script complete."
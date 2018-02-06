#!/bin/bash

#################################################################################################################################
# community-builds-from-source.sh
#     by Jeremy Wentworth
#
# Modified by Kent Williams chaircrusher@gmail.com
# Modified by Gerhard Brandt gbrandt@cern.ch
#
# This script pulls down the VCV Rack community repo, finds source urls, pulls down source repos, and builds plugins.
#
# This script requires:
#	  bash - brew install bash # on mac
#     git - https://git-scm.com/
#     VCV Rack dev env - https://github.com/VCVRack/Rack#setting-up-your-development-environment
#
# Copy this script into:
#    Rack/plugins
#
# Run this in Rack/plugins:
#    . community-builds-from-source.sh
#
#################################################################################################################################

nproc=`sysctl -n hw.physicalcpu` #mac
#nproc=`nproc` #linux

echo $nproc

# check for the community repo locally
echo [Update community repo]
echo
if [ -d "community" ]; then
	pushd community
		# discard any changes
		git reset HEAD --hard

		# update the community repo if it exists
		if ! git pull; then
			git status
			exit
		fi
	popd
else
	# community repo does not exist so pull it down
	git clone https://github.com/VCVRack/community
fi
echo

buildfails=""

# the strategy is that you want the 'latest and greatest' version of
# each plugin -- the master branch.  But some plugins won't compile
# unless you check out a specific git label. So the versionMap lets
# you look up that version below when checking out source.
declare -A versionMap
versionMap=([Autodafe]=skip [Autodafe-Drums]=skip [NYSTHI]=skip
	[southpole-vcvrack]=skip 
	[RJModules]=master [DrumKit]=master [VCV-Rack-Plugins]=master)

# helper function to see if a particular key is in an associative array
exists(){
  if [ "$2" != in ]; then
    echo "Incorrect usage."
    echo "Correct usage: exists {key} in {array}"
    return
  fi
  eval '[ ${'$3'[$1]+muahaha} ]'
}

# loop through the json in the community repo
for gitPlugin in $(cat community/plugins/*.json | grep \"source\" | awk -F'"' '{print $4}')
do
	#strip eventual extension
	gitPlugin=${gitPlugin%.git}
	# get the folder name and see if we already haave it locally
	pluginDirName=$(echo $gitPlugin | awk -F'/' '{print $5}')
	echo
	echo [$pluginDirName]
	if exists ${pluginDirName} in versionMap
	then
		echo ${versionMap[${pluginDirName}]}
		if [ ${versionMap[${pluginDirName}]} == "skip" ]
	 	then
		 	echo [$pluginDirName SKIPPING]
			continue;
		fi
	fi	

	#echo ${gitPlugin%.git}
	if [ -d "$pluginDirName" ]; then
		echo "[$pluginDirName exists]"
	else
		echo "[$pluginDirName does not exist yet]"
		userNameUrlPart=$(echo $gitPlugin | awk -F'/' '{print $4}')
		#git clone ${gitPlugin%.git} #strip eventual extension
		git clone $gitPlugin #NOTE: not all plugins are on github, sonus is on gitlab
	fi

	# if there's a problem with checkout everything goes to hell
	if [ ! -d ${pluginDirName} ] ; then
		 echo "[$pluginDirName] clone failed!!!"
		 exit 	
		 continue;
	fi

	# change to the repo dir
	pushd $pluginDirName

	# Some devs don't have a .gitignore so you can't pull until you do something with the changed files.
	#git reset HEAD --hard #discards any changes - we could do `git stash` here instead

	# pull down the latest code
	git fetch
	if exists ${pluginDirName} in versionMap 
	then
		git checkout ${versionMap[${pluginDirName}]}
	else
		latest=`git describe --tags --abbrev=0`
		if [[ ! -z $latest ]]; then
			echo "[$pluginDirName Latest tag: $latest]"
			git checkout $latest
		else
			echo "[$pluginDirName no tags - using master !!!]"
			git checkout master
		fi
	fi

	# try to update submodules if there are any
	git submodule update --init --recursive

	# clean old builds (might not be needed but can prevent issues)
	#make clean

	make -j$nproc dep

	# finally, build the plugin
	if make -j$nproc
	then
		 true; # say nothing
	else
		 buildfails="${buildfails} ${pluginDirName}"
	fi

	# go back to the last dir
   popd

done

echo "BUILD FAILURES: ${buildfails}"

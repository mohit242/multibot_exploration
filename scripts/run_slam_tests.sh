
mazeSizeMin=2
mazeSizeMax=6
testCount=30
rosLaunchTimeout=1800
#YOU NEED TO SPECIFY CORRECT DISPLAY TO GET STAGE SIMULATOR RUNNING
DISPLAY=:100

curTimeStamp=`echo $(date +'%s')`
status=`rospack find explorer`/simulation_status/robot_0.finished
testLogFile=~/test_results/log$curTimeStamp.log

for ((mazeSize=$mazeSizeMin; mazeSize<=$mazeSizeMax; mazeSize++))
do
	mainRes=~/test_results/all/res$mazeSize.log
	echo -e "mean(exploration_time)\tmean(required_goals)\tmean(travel_path_overall)\tmean(unreachable_goals)\tmean(complete)\tmean(map_error)" >> $mainRes
	
	mazeFileName=maze$mazeSize
	mazeFileName+=x$mazeSize.png
	worldDir=`rospack find explorer`/world
	
	#create test directory
	curTestMazeDir=~/test_results/$mazeSize
	curTestMazeDir+=_$mazeSize
	curTestMazeDir+=_$curTimeStamp
	mkdir $curTestMazeDir
	mkdir $curTestMazeDir/all
	allResFile=$curTestMazeDir/all/allres.log
	echo -e "exploration_time\trequired_goals\ttravel_path_overall\tunreachable_goals\tcomplete\tmap_error" >> $allResFile
	
	# create maze
	## comment this section if you want to test using old maps
	cd ~/my_ws/amaze
	./amaze $mazeSize $mazeSize
	convert maze.bmp -bordercolor black -border 1 $worldDir/$mazeFileName
	
	#copy map to later compare it to results
	convert maze.bmp $curTestMazeDir/all/$mazeFileName
	
	#copy map to launch it at stage
	cp $worldDir/$mazeFileName $worldDir/small_world.png
	
	#now run tests on this maze
	for ((i=1; i<=$testCount; i++))
	do
		echo "Launched test #$i for maze $mazeFileName"
		rm $status
		timeout $rosLaunchTimeout roslaunch explorer just_explore_one.launch &>> $testLogFile &
		rospid=`ps | grep roslaunch | xargs | cut -d' ' -f1`

		# wait until exploration is finished, or timeout is exceeded
		sleep 5
		waited=0
		until [ -e $status ] || [ -z "$rospid" ];
		do
			echo "[$waited] Waiting for $status to be created or roslaunch [$rospid] to finish"
			sleep 5
			rospid=`ps | grep roslaunch | xargs | cut -d' ' -f1`
			let "waited=5+$waited"
			if [ "$waited" -ge "$rosLaunchTimeout" ]
			then
				kill $rospid
			fi
		done

		echo "Waiting to ensure we can continue"
		sleep 20
		echo "Killing ROS (if not finished yet)"
		kill $rospid
		wait $rospid
		sleep 30
		
		# in case ROS not finished, there will be another file about exploration
		if [ -e $status ]
		then
			expLog=exploration.log
		else
			expLog=exploration.log.tmp
		fi

		echo "Saving generated logs"
		#save logs from test to its directory
		mv ~/logs ~/.ros/log/latest
		cd ~/.ros/log
		curLogDir=~/.ros/log/`ls -td -- */ | head -n 1 | cut -d"/" -f1`
		curTestDir=$curTestMazeDir/$i
		cp -r $curLogDir $curTestDir
		rm -rf $curLogDir

		# copy created map to test directory, convert it to png, trim and save it at all folders
		convert $curTestDir/logs/map_merger/robot_0/local.pgm -flip -trim -brightness-contrast -60x80 $curTestDir/map.png
		cp $curTestDir/map.png $curTestMazeDir/all/$i.png
		echo "Copied created map to $curTestMazeDir/all/$i.png"
		mainMapRes=~/test_results/all/$mazeSize
		mainMapRes+=_$i.png
		cp $curTestMazeDir/all/$i.png $mainMapRes
		echo "Copied created map to $mainMapRes"
		
		echo "Adding results to list:"
		#now add results from exploration.log to list
		cd $curTestDir/logs/explorer/robot_0
		resFile=$curTestDir/res.log
		echo -n `cat $expLog | grep exploration_time | cut -d'=' -f2 | cut -d' ' -f2` >> $resFile
		echo -e -n '\t' >> $resFile
		echo -n `cat $expLog | grep required_goals | cut -d'=' -f2 | cut -d' ' -f2` >> $resFile
		echo -e -n '\t' >> $resFile
		echo -n `cat $expLog | grep travel_path_overall | cut -d'=' -f2 | cut -d' ' -f2` >> $resFile
		echo -e -n '\t' >> $resFile
		echo -n `cat $expLog | grep unreachable_goals | cut -d'=' -f2 | cut -d' ' -f2` >> $resFile
		echo -e -n '\t' >> $resFile
		echo -n `cat $expLog | grep complete | cut -d'=' -f2 | cut -d' ' -f2 | tail -n 1` >> $resFile
		echo -e -n '\t' >> $resFile
		
		#now compare maps we got to source
		cd $curTestMazeDir/all
		convert $mazeFileName -scale `identify $i.png | cut -d" " -f3`! temp.png
		compare -metric AE -fuzz 40% temp.png $i.png diff$i.png &>> $resFile
		
		# save result to parent's folder
		cat $resFile >> $allResFile
		cat $resFile
		cd ~
	done
	
	# now process data we got for current mazeSize
	datamash -H mean 1 mean 2 mean 3 mean 4 mean 5 mean 6 < $allResFile | tail -n 1 >> $mainRes
done
echo "Testing complete"

#! /bin/bash

where="."
home_dir="/tmp/.jarquery"
work_dir="$home_dir/work"
jar_work_dir="$home_dir/work/jar"
war_work_dir="$home_dir/work/war"
new_work_dir="$home_dir/work/new"
history_dir="$home_dir/history/`date +%s`"
ignore="/opt/camiant/webapps"

clear_history=false
update_script=update.sh
update_package=update.tar.gz
verbose=false
assume_yes=false

usage="USAGE: \n
\t -d <query where> -q <query what> \n
  or \n
\t -d <query where> -u <update with> \n
\nGENERAL OPTIONS: \n
\t -c \t clear history data \n
\t -h \t display a help message and then quit \n
\t -v \t run with a lot of debugging output \n
\t -y \t assume that the answer to any question which would be asked is yes \n
\nEXAMPLES: \n
\t In the directory /opt/product1, finds jar & war files which contains file services.abc.Foo.class. \n
\t\t ./jarUtil.sh -d /opt/product1 -q services/abc/Foo.class \n\n
\t In the directory /opt/product1, replaces jar & war files with all the files under the directory ./newChanges. \n
\t\t ./jarUtil.sh -d /opt/product1 -u ./newChanges/ -y -v\n"

# Set up the workspace.
setUp() {
    rm -rf $work_dir
    mkdir -p $jar_work_dir
    mkdir -p $war_work_dir
    mkdir -p $new_work_dir
    mkdir -p $history_dir
}

# Search on all jar files under the specified directory.
# @param directory contains jar files
# @param query condition
# @param extracted from
searchOnJars() {
    jar_files=`find $1 -name "*.jar" ! -type l`
    for f in $jar_files
    do
        if [ ${f:0:${#ignore}} = $ignore ]
        then
            trace "Ignore $f."
            continue;
        fi;
        
        found=`jar tf $f | grep $2 | wc -l`
        if [ $found -gt 0 ]
        then
            if [ $3 ]
            then
                echo -e "$3 \n   -> ${f:${#work_dir}+1}"
            else
                echo $f 
            fi;
        fi
    done
}

# Search on all war files under the specified directory.
# @param directory contains war files
# @param query condition
searchOnWars() {
    war_files=`find $1 -name "*.war" ! -type l`
    cd $work_dir
    for f in $war_files
    do
        cp $f $work_dir
        jar xf `basename $f`
        searchOnJars $work_dir $2 $f
        rm -rf *
    done
}

# Update all jar/war files under the specified directory with the specified directory
# @param directory contains jar/war files
# @param directory contains new files
update() {
    createUpdateScript
    updateJars $1 $2
    updateWars $1 $2
    createUpdatePackage
    
    echo "" 
    echo " !!! Please go to folder $new_work_dir, then run $update_script. !!!"
    echo " OR "
    echo " !!! Copy $new_work_dir/$update_package to the other machines, extract it, then run $update_script file. !!!"
}

createUpdateScript() {
    cd $new_work_dir
    echo '#! /bin/bash' > $update_script
    chmod +x $update_script
}

createUpdatePackage() {
    cd $new_work_dir
    tar zcf $update_package ./
}

# Update all jar files under the specified directory with the specified directory
# @param directory contains jar files
# @param directory contains new files
# @param extracted from
updateJars() {
    trace "Start to update jars."
    cd $jar_work_dir
    
    war_updated=false
    
    new_files=`find $2 -type f`
    jar_files=`find $1 -name "*.jar" ! -type l`
    
    for j in $jar_files
    do
        if [ ${j:0:${#ignore}} = $ignore ]
        then
            trace "Ignore $j."
            continue;
        fi;
        
        trace "Start to update $j."
        
        jar_name=`basename $j`
        jar_updated=false
        jar_copyed=false
        
        for n in $new_files
        do
            n_relative=${n:${#2}+1}
            trace "Search $n_relative in $j."
            guess_updates=`jar tf $j | grep $n_relative`
            
            if [ $guess_updates ]
            then
                if [ $jar_copyed = false ]
                then
                    trace "Found."
                    trace "Copy $j to $jar_work_dir."
                    cp $j $jar_work_dir
                    jar_copyed=true
                    jar xf $jar_name
                fi
                
                for g in $guess_updates
                do
                    while true
                    do
                        if [ $assume_yes = false ]
                        then
                            printf " --> update %s in %s with %s [y/N]: " $g $j $n
                            read yes_no
                        else
                            printf " --> update %s in %s with %s\n" $g $j $n
                            yes_no='y'
                        fi
                        
                        case $yes_no in
                            y|Y|YES|yes|Yes)
                                trace "Update $n_relative."
                                jar_updated=true
                                
                                if [ $war_updated = false ]
                                then
                                    war_updated=true
                                fi
                                
                                cp -f $n $g
                                break;;
                            n|N|NO|no|No)
                                echo -e "   --> ignored $g"
                                break;;
                            *) echo "Please enter y or n"
                                ;;
                        esac
                    done
                done
            fi
        done
        
        if [ $jar_updated = true ]
        then
            # back up the original jar
            trace "Backup $j to $history_dir."
            mv $jar_name $history_dir
            
            # create a new jar
            trace "Archive a new jar file $jar_name under $jar_work_dir."
            jar cf $jar_name *
            if [ $1 = $war_work_dir ]
            then
                trace "Copy the new jar file to $j."
                cp -f $jar_name $j
            else
                trace "Copy the new jar file to $new_work_dir."
                cp -f $jar_name $new_work_dir
                echo "cp -f $jar_name $j" >> "$new_work_dir/$update_script"
            fi;
            
            # clean up
            trace "Clean up $jar_work_dir."
            rm -rf *    
        fi
    done
}

# Update all war files under the specified directory with the specified directory
# @param directory contains war files
# @param directory contains new files
updateWars() {
    trace "Start to update wars."
    cd $war_work_dir
    
    war_files=`find $1 -name "*.war" ! -type l`
    
    for f in $war_files
    do
        trace "Start to update $f."
        war_name=`basename $f`
        
        trace "Copy $f to $war_work_dir."
        cp $f $war_work_dir
        jar xf $war_name
        
        war_updated=false
        printf " * %s\n" $f
        updateJars $war_work_dir $2
        
        cd $war_work_dir
        if [ $war_updated = true ]
        then
            trace "Backup $war_name to $history_dir."
            mv $war_name $history_dir
            trace "Archive a new war file $war_name under $war_work_dir."
            jar cf $war_name *
            trace "Copy the new war file to $new_work_dir."
            cp -f $war_name $new_work_dir
            echo "cp -f $war_name $f" >> "$new_work_dir/$update_script"
        fi
        
        # clean up
        trace "Clean up $war_work_dir."
        rm -rf *
    done
}

# Print debugging info if verbose is enabled.
# @param message
trace() {
    if [ $verbose = true ]
    then
        echo "[INFO] " $1
    fi
}

# Kick off!
while getopts "q:u:d:chvy" arg
do
    case $arg in
        c):
            clear_history=true
            ;;
        d):
            where=$OPTARG
            ;;
        q):
            query=$OPTARG
            ;;
        u):
            update=`cd $OPTARG && pwd`
            ;;
        h):
            echo -e $usage
            exit 0
            ;;
        v):
            verbose=true
            ;;
        y):
            assume_yes=true
            ;;
        ?):
            echo -e $usage
            exit 1
            ;;
    esac
done

where=`cd $where && pwd`

setUp

if [ $query ]; then
    trace "To search $query from $where"
    searchOnJars $where $query
    searchOnWars $where $query
elif [ $update ]; then
    trace "To update $where with $update"
    update $where $update
elif [ $clear_history = true ]; then
    trace "To clear history"
    rm -rf $home_dir/history
else
    echo -e $usage
fi;


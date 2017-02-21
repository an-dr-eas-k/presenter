#!/bin/bash

crt="VGA1"
laptop="LVDS1"
export maindir="$HOME/usr/presentation/"
export configdir="$HOME/usr/presentation/etc/"
export bindir="$HOME/usr/presentation/bin/"

##################################################
# no need to change the following code
geometry="1024x768" # ordinary beamer
# geometry="1920x1200" # binfo monitore
# geometry="1280x1024" # dell office monitor
vncdisplay="20"
debug=$(true)
pidfileMaster=/tmp/presentation.master.pid
pidfileSlave=/tmp/presentation.slave.pid

mode="$1"
pdfFile="$2"

quit(){
	echo "usage: $0 [on|prepare|extprepare|off] <pdfFile>"
	exit;
}

if [ "$mode" != "on" ] && [ "$mode" != "off" ] && [ "$mode" != "prepare" ] && [ "$mode" != "extprepare" ] ; then
	quit;
fi;

if [ "$mode" == "on" ] || [ "$mode" == "prepare" ] || [ "$mode" == "extprepare" ]; then
	if [ -e "$pdfFile" ]; then
		export PRESENTATIONFILE=$(pwd)/$pdfFile;
		export PRESENTATIONDIR=$(dirname $(pwd)/$pdfFile);
	else
		export PRESENTATIONDIR=$(pwd);
		unset PRESENTATIONFILE;
#		quit;
	fi;
fi

panels=$( \
	gconftool-2 --get /apps/panel/general/toplevel_id_list| \
	tr -d [\[\]]| \
	tr "," " ");

orientPanels(){
	for i in $panels; do
		if grep -i top <(echo ${i}) &>/dev/null; then
			gconftool-2 --set --type String /apps/panel/toplevels/${i}/orientation top; 
		elif grep -i bottom <(echo ${i}) &>/dev/null; then
			gconftool-2 --set --type String /apps/panel/toplevels/${i}/orientation bottom; 
		fi
	done
}

placePanels(){
	for i in $panels; do
		gconftool-2 --set --type Integer /apps/panel/toplevels/${i}/monitor 0; 
	done
}

replacePanels(){
	for i in $panels; do
		gconftool-2 --unset /apps/panel/toplevels/${i}/monitor;
	done
}

showPanels(){
	for i in $panels; do
		gconftool-2 --set --type bool /apps/panel/toplevels/${i}/auto_hide false;
	done;
}

hidePanels(){
	for i in $panels; do
		gconftool-2 --set --type bool /apps/panel/toplevels/${i}/auto_hide true;
	done;
}

switchWindows(){
	gconftool-2 --unset /apps/metacity/global_keybindings/switch_windows
	gconftool-2 --unset /apps/metacity/global_keybindings/cycle_windows
}

cycleWindows(){
	gconftool-2 --set --type String /apps/metacity/global_keybindings/switch_windows "Disabled"
	gconftool-2 --set --type String /apps/metacity/global_keybindings/cycle_windows "<Alt>Tab"
	gconftool-2 --set --type String /apps/metacity/global_keybindings/switch_windows "<Alt>Escape"
}

startVncServer(){
	mkdir $HOME/.vnc/ &>/dev/null
# start the vncserver only if it is not already running
	if [ ! -e $HOME/.vnc/${hostname}:${vncdisplay}.pid ]; then 
		if [ -e $HOME/.vnc/xstartup ]; then
			mv $HOME/.vnc/xstartup $HOME/.vnc/xstartup.presentationsave
			ln -s ${configdir}/vnc/xstartup $HOME/.vnc/xstartup;
		fi
		vncserver :${vncdisplay} -name presentation -geometry ${geometry} -depth 16 &>/dev/null
	fi
}

stopPresentation(){
	killall vncviewer &>/dev/null
	rm ${pidfileMaster} ${pidfileSlave} &>/dev/null
	vncserver -kill :${vncdisplay} &>/dev/null
	if [ -e $HOME/.vnc/xstartup.presentationsave ]; then
		rm $HOME/.vnc/xstartup
		mv $HOME/.vnc/xstartup.presentationsave $HOME/.vnc/xstartup
	fi
}

startSlave(){ # the beamer terminal
	if \
		[ -e ${pidfileSlave} ] && \
		[ x$(ps h -o comm -p $( cat ${pidfileSlave} )) == "xvncviewer" ];
	then
		echo "found slave. doing nothing"
		return
	fi
	vncviewer \
		-Shared -ViewOnly -passwd ~/.vnc/passwd -passwdInput false \
		-geometry ${geometry}+0+768 \
		:${vncdisplay} &>/dev/null &
	slavePid=${!}
	echo ${slavePid} > ${pidfileSlave}
	sleep 1
	slaveid=$(getSlaveId)
	echo ${slaveid}
#	wmctrl -r ":ACTIVE:" -b add,fullscreen
#	wmctrl -r "TigerVNC: presentation" -b add,fullscreen
	wmctrl -i -r ${slaveid} -b add,fullscreen
}

startMaster(){ # the local terminal
	if \
		[ -e ${pidfileMaster} ] && \
		[ x$(ps h -o comm -p $( cat ${pidfileMaster} )) == "xvncviewer" ];
	then
		echo "found master. doing nothing"
		return
	fi
	vncviewer \
		-Shared -passwd ~/.vnc/passwd -passwdInput false \
		-geometry ${geometry}+0+0 \
		:${vncdisplay} &>/dev/null &
	masterPid=${!}
	echo ${masterPid} > ${pidfileMaster}
}

getSlaveId(){
	for i in $(
		xwininfo -root -children -all | \
			grep "TigerVNC: presentation" | \
			awk '{print $1}'
		); do
		echo ${i} >/dev/stderr
		if xprop -id ${i} "WM_COMMAND" | grep -q "\-ViewOnly"; then
			printf "slave window_id successfully found: %s" "${i}" >/dev/stderr
			echo "${i}"
			return
		fi
	done
}

extendDesktop(){
	monitorStatus=$(xrandr |grep ${crt} | cut -d " " -f 2)
	if ! ${debug} && [ "x${monitorStatus}" == "xdisconnected" ]; then
		echo "monitor ${crt} not connected" 1>&2
		exit
	fi
	xrandr --addmode ${crt} ${geometry}
	xrandr --output ${crt} --below ${laptop} --mode ${geometry}
}

xdaliClock(){
	devilFile=$HOME/.devilspie/presentationClock.ds
	clockPidFile=/tmp/presentation.clock.pid;
	if [ $mode == "on" ]; then 
		cat > $devilFile <<-EOF
			; generated_rule xdaliclock
			( if 
			( and 
			( matches ( window_class ) "[xX][dD]ali[cC]lock" )
			) 
			( begin 
			( undecorate )
			( println "match" )
			)
			)
		EOF
		killall devilspie
		devilspie &
		xdaliclock  -geometry -10+798 -fn BUILTIN1 &
		echo "$!" > $clockPidFile;
	else
		kill $(cat $clockPidFile) > /dev/null;
		rm $clockPidFile;
		rm $devilFile;
		killall devilspie
		devilspie &
	fi
}

checkDependency(){
	missing="";
	for i in \
			"/usr/bin/wmctrl" \
			"/usr/bin/xprop" \
			"/usr/bin/xwininfo" \
			"/usr/bin/xrandr" \
			"/usr/bin/vncserver" \
			"/usr/bin/vncviewer" \
			"/usr/bin/fluxbox" \
			"/usr/bin/gconftool-2" \
			"/usr/bin/awk" \
		; do
		if [ ! -e "$i" ]; then
			missing="${missing} ${i}"
		fi
	done
	if [ -n "${missing}" ]; then
		printf "missing dependency:%s\n" "$missing";
		exit
	fi
}

checkDependency;
if [ "$mode" == "on" ]; then
	extendDesktop;
	placePanels;
	showPanels;
	orientPanels;
	startVncServer;
	startSlave;
	startMaster
	cycleWindows;
#	xdaliClock on;
elif [ "$mode" == "prepare" ]; then
	startVncServer;
	startMaster;
elif [ "$mode" == "extprepare" ]; then
	placePanels;
	showPanels;
	orientPanels;
	startVncServer;
	startMaster;
else
	stopPresentation;
	replacePanels;
	xrandr --output ${crt} --off
	hidePanels;
	orientPanels;
	switchWindows;
#	xdaliClock off;
fi;

#vim: foldmethod=marker

if [ $(tty) = "/dev/tty1" ]; then
  startx
fi

xhost +

feh --bg-scale /home/kannar/Pictures/V4.png

#!/bin/sh

setxkbmap fr

#systemctl --user set-environment DISPLAY=:0

exec "i3"

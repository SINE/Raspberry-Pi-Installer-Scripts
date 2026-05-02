#!/bin/bash

# Unload
sudo dtoverlay -r drm-minipitft114
sudo modprobe -r fb_st7789v
sudo modprobe -r fbtft

# Compile and install into kernel module tree
sudo make install

# Load again
sudo modprobe fbtft
sudo modprobe fb_st7789v
sudo dtoverlay drm-minipitft114
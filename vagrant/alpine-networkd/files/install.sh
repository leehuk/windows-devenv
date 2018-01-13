#!/bin/bash

sudo apk update
sudo apk upgrade

sudo apk add dnsmasq
sudo cp /tmp/dnsmasq.conf.vagrant /etc/dnsmasq.conf

sudo rc-update add dnsmasq

sudo /etc/init.d/dnsmasq start

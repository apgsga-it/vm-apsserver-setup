#!/usr/bin/env bash
firewall-cmd --permanent --add-port=8080/tcp
firewall-cmd --reload


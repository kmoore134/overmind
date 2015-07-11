#############################################################################
# Makefile for building: overmind
#############################################################################

PREFIX?= /usr/local

####### Install

all:

install_doinstall:
	sh install $(PREFIX)

install:  install_doinstall

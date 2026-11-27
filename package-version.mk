# Shared OpenWrt package version resolver. Each package keeps a VERSION file
# (or a relative symlink to the repository's canonical VERSION) beside this
# include, so feed installs and SDK staging use the same lookup rule.
PKG_VERSION_FILE:=$(dir $(abspath $(lastword $(MAKEFILE_LIST))))VERSION
ifeq ($(wildcard $(PKG_VERSION_FILE)),)
  $(error Missing VERSION beside $(lastword $(MAKEFILE_LIST)))
endif
PKG_VERSION:=$(strip $(shell sed -E 's/-rc\./_rc/' "$(PKG_VERSION_FILE)"))
ifeq ($(PKG_VERSION),)
  $(error Empty VERSION beside $(lastword $(MAKEFILE_LIST)))
endif

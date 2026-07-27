ifeq ($(OS),Windows_NT)
BUILD = powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1
TARGET_OPT = -Target
ARCH_OPT = -HostArch
LIST_OPT = -List
CLEAN_OPT = -Clean
else
BUILD = sh ./build.sh
TARGET_OPT = --target
ARCH_OPT = --arch
LIST_OPT = --list
CLEAN_OPT = --clean
endif

.PHONY: all arm host x86 x64 sanitize test vanilla commander list clean

all:
	$(BUILD)

arm:
	$(BUILD) $(TARGET_OPT) arm

host:
	$(BUILD) $(TARGET_OPT) host

x86:
	$(BUILD) $(TARGET_OPT) host $(ARCH_OPT) x86

x64:
	$(BUILD) $(TARGET_OPT) host $(ARCH_OPT) x64

sanitize:
ifeq ($(OS),Windows_NT)
	$(BUILD) $(TARGET_OPT) host -Sanitize
else
	$(BUILD) $(TARGET_OPT) host --sanitize
endif

test: arm
ifeq ($(OS),Windows_NT)
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/rom_tools.ps1
else
	sh ./tests/rom_tools.sh
endif

vanilla:
	$(BUILD) vanilla

commander:
	$(BUILD) commander

list:
	$(BUILD) $(LIST_OPT)

clean:
	$(BUILD) $(CLEAN_OPT)

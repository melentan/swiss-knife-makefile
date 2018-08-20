# Author : Corentin GUILLEVIC
# Require : GNU sed (\U format), GNU coreutils 8.23 (for --relative-to of realpath)
VERSION := 0
SUBVERSION := 8
# Default target is 'all'
.DEFAULT_GOAL := all
.PHONY: all clean $(foreach format, $(LIST_FORMATS), ${${format}_SRC}-clean) $(foreach format, $(LIST_FORMATS), ${${format}_SRC}-clean-extra) compress-src compress-obj what-obj
# Name of this Makefile's top directory
BASEDIR := $(shell basename $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
TAR-EXCLUDE := .tar-exclude

# Include user variables, ignore error if file doesn't exist
-include user.mk

##################### LATEX ################################
# Latex compiler
TEXC := pdflatex
# Options for Latex compiler
TEXFLAGS := -synctex=1 -interaction=nonstopmode -halt-on-error $(TEXFLAGS_EXTRA)
TEXFLAGS_EXTRA = -output-directory $(dir $<)/texobjs/
TEX_TAR_EXCLUDE = .textmp
TEX_SRC := tex
TEX_DST := pdf

%.$(TEX_DST): %.$(TEX_SRC)
	mkdir -p $(dir $@).textmp/
	if [ $$(find $(dir $@) -name $(notdir $@) -print -quit | wc -l) -eq 0 ] ; then \
		(cd $(dir $@) && $(TEXC) $(TEXFLAGS) -output-directory .textmp/ $(notdir $<)) \
	fi
	(cd $(dir $@) && $(TEXC) $(TEXFLAGS) -output-directory .textmp/ $(notdir $<))
	mv $(dir $@).textmp/$(notdir $@) $@

# Store .tex filenames, then for each one delete its .aux/.log/.out/.nav/.toc/.synctex.gz files
$(TEX_SRC)-clean-extra::
	$(eval texobj = $(filter %.$(TEX_SRC), $(SOURCES)))
	$(foreach obj, $(texobj), rm -f $(dir $(obj))/.textmp/$(basename $(notdir $(obj))).* ;)
##################### MARKDOWN ################################
# Markdown compiler
MDC := pandoc
# Options for markdown compiler
MDFLAGS := -s -N --toc --toc-depth=4
# Extra options
MDFLAGS_EXTRA = --variable pagetitle="$$(basename $(notdir $@) .$(MD_DST) | sed 's/./\U&/')"
MDFLAGS_EXTRA_CSS = -c $(shell realpath -e --relative-to="$(dir $<)" $(CSS))
# The first CSS found will be used
CSS ?= $(shell find -type f -name "*.css" -print -quit)
MD_SRC := md
MD_DST := html

# Target for markdown files, take .css if it exists
%.$(MD_DST): %.$(MD_SRC)
ifneq (,$(wildcard $(CSS)))
	$(MDC) $(MDFLAGS) $(MDFLAGS_EXTRA) $(MDFLAGS_EXTRA_CSS) -o $@ $< 
else 
	$(MDC) $(MDFLAGS) $(MDFLAGS_EXTRA) -o $@ $< ;
endif

define RECURSIVE_MD_INDEX
# Create index.md files
	$(foreach dira, $(sort $(dir $(filter %.$(MD_SRC), $(SOURCES)))), \
		(cd $(dira) ; echo '# $(notdir $(shell pwd))\n' > index.md) ; \
	)
# https://unix.stackexchange.com/questions/13464/is-there-a-way-to-find-a-file-in-an-inverse-recursive-search/13474
# For each index.md file, register it to its superior
# The \U format of sed is available only in GNU sed (not POSIX sed)
	$(foreach dira, $(sort $(dir $(filter %.$(MD_SRC), $(SOURCES)))), \
	cd $(dira) ; path="$$(basename $(dira))/index.html" ; while [ 1 ] ; do \
	if [ "$$PWD/" = "$(dir $(abspath $(lastword $(MAKEFILE_LIST))))" ] ; then \
		break ; \
	elif [ -e '../index.md' ] ; then \
		grep '## Directories' ../index.md > /dev/null ; \
		if [ $$? = 1 ] ; then \
			echo "## Directories\n" >> ../index.md ; \
		fi ; \
		echo "* [$$(dirname $$path | sed 's/./\U&/')]($$path)" >> ../index.md ; \
		break ; \
	else \
		path=$$(basename $$PWD)/$${path} ; \
		cd ../ \
		continue ; \
	fi ;\
done
	)
	$(foreach dira, $(sort $(dir $(filter %.$(MD_SRC), $(SOURCES)))), \
		(cd $(dira) ; echo "\n## Links\n" >> index.md ; find -maxdepth 1 -type f -name "*.md" ! -name "index.md" -printf '%f\n' | sort | sed -r 's/(.+)\.md/\* \[\u\1\]\(\1.html\)/' >> index.md)
		$(MAKE) $(dira:./%=%)index.html
	)
endef

# Generate indexes
$(MD_SRC)-index:
	$(call RECURSIVE_MD_INDEX)

# Detect some characters
$(MD_SRC)-grep-unwanted-char:
	grep --color --line-number -E '…|«|»|’|“|–' $(filter %.$(MD_SRC), $(SOURCES)) || true

# Delete indexes
$(MD_SRC)-clean-extra::
	$(eval texobj = $(filter %index.$(MD_SRC), $(SOURCES)))
	$(foreach obj, $(texobj), rm -f $(obj) $(obj:%.md=%.html);)
##################### SVG ################################
# SVG converter
SVGC := inkscape
# Options for SVG converter
SVGFLAGS := -z
SVG_SRC := svg
SVG_DST := png

%.$(SVG_DST): %.$(SVG_SRC)
	$(SVGC) $(SVGFLAGS) -e $@ $<
##################### FLAC ################################
# FLAC converter
FLACC := ffmpeg
# Options for FLAC converter
FLACFLAGS := -b:a 320k
# Extra options
FLACFLAGS_EXTRA = -i $(dir $<)/cover.* -map_metadata 0 -map 0 -map 1 # Add cover
FLAC_SRC := flac
FLAC_DST := mp3

# Target for .flac files, take cover if it exists
%.$(FLAC_DST): %.$(FLAC_SRC)
	@# If file exists
	$(if $(wildcard $(dir $<)/cover.*), \
		$(FLACC) -i $< $(FLACFLAGS_EXTRA) $(FLACFLAGS) $@, \
		$(FLACC) -i $< $(FLACFLAGS) $@)
##########################################################
# List of source format
LIST_FORMATS := MD SVG TEX FLAC

# Directory of search
ifeq ($(DIR),)
	DIR := ./
else
	saved-output:=$(abspath $(DIR))
	# If $(DIR) is out of tree (not allowed)
	ifeq ($(saved-output), $(saved-output:$(CURDIR)%=%))
$(error $(saved-output) is out of tree)
	endif
endif
# Search all files whose format is supported
SOURCES = $(shell find $(DIR) \( -false $(foreach format, $(LIST_FORMATS), -o -name "*.${${format}_SRC}") \) -print)

# Define objects to generate
OBJECTS := $(SOURCES)
$(foreach format, $(LIST_FORMATS), \
	$(eval saved-output = $(OBJECTS:${${format}_SRC}=${${format}_DST})) \
	$(eval OBJECTS := $(saved-output));)

all: $(OBJECTS)

compress: compress-obj compress-src

# Create an archive containing all source files but not :
# * All objects ("compiled" sources)
# * Anterior sources and objects .tar.gz
# * Excluded files by the type's object (middle files)
# * Files mentionned by ${TAR-EXCLUDE}
# * Internal files of the VCS
compress-src:
	tar --transform 's|^\./|$(BASEDIR)/|' \
		--recursion \
		$(foreach obj, $(OBJECTS),--exclude='$(obj)') \
		$(foreach format, $(LIST_FORMATS),$(if ${${format}_TAR_EXCLUDE},--exclude='${${format}_TAR_EXCLUDE}',)) \
		--exclude='./$(BASEDIR)-src.tar.gz' \
		--exclude='./$(BASEDIR)-obj.tar.gz' \
		--exclude-ignore=$(TAR-EXCLUDE) \
		--exclude-vcs \
		-cf $(BASEDIR)-src.tar.gz .

# Create an archive containing all object files but not :
# * All sources
# * That Makefile and its user.mk extension
# * Anterior sources and objects .tar.gz
# * Excluded files by the type's object (middle files)
# * Files mentionned by ${TAR-EXCLUDE}
# * ${TAR-EXCLUDE} itself
# * Internal files of the VCS
compress-obj:
	tar --transform 's|^\./|$(BASEDIR)/|' \
		--recursion \
		--exclude='./Makefile' \
		--exclude='./user.mk' \
		$(foreach format, $(LIST_FORMATS), --exclude='*.${${format}_SRC}') \
		$(foreach format, $(LIST_FORMATS), $(if ${${format}_TAR_EXCLUDE},--exclude='${${format}_TAR_EXCLUDE}',)) \
		--exclude='./$(BASEDIR)-src.tar.gz' \
		--exclude='./$(BASEDIR)-obj.tar.gz' \
		--exclude='$(TAR-EXCLUDE)' \
		--exclude-ignore=$(TAR-EXCLUDE) \
		--exclude-vcs \
		-cf $(BASEDIR)-obj.tar.gz .

clean: $(foreach format, $(LIST_FORMATS), ${${format}_SRC}-clean-extra)
	rm -f $(OBJECTS)

# Clean by format
$(foreach format, $(LIST_FORMATS), ${${format}_SRC}-clean):: %-clean:
	rm -f $(filter %.${$(shell echo $* | tr a-z A-Z)_DST}, $(OBJECTS))

# Empty recipe to possibly be overloaded
$(foreach format, $(LIST_FORMATS), ${${format}_SRC}-clean-extra):: %-clean-extra: ;

what-obj:
	@$(foreach obj, $(OBJECTS), echo $(obj);)

version:
	@echo "Makefile Converter $(VERSION).$(SUBVERSION)"
	@echo "Written by Corentin Guillevic"

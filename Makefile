ASM   := wla-z80
LINK  := wlalink
BUILD := build
ROM   := $(BUILD)/smsggdj.sms
GGROM := $(BUILD)/smsggdj.gg

# Versioned copies for distribution: str_version ("V0.27") -> a filename-safe
# tag with no spaces or dots, e.g. build/smsggdj_v0_27.sms. The canonical names
# above stay stable for `make run` and the tooling.
VTAG  := $(shell sed -n 's/^str_version:.*"\([^"]*\)".*/\1/p' src/main.asm | tr -d ' ' | tr '.' '_' | tr 'A-Z' 'a-z')
ifeq ($(strip $(VTAG)),)
VTAG  := dev
endif
VROM   := $(BUILD)/smsggdj_$(VTAG).sms
VGGROM := $(BUILD)/smsggdj_$(VTAG).gg

all: $(ROM) $(GGROM) $(VROM) $(VGGROM)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/font.bin: tools/makefont.py | $(BUILD)
	python3 tools/makefont.py $@

$(BUILD)/notes.inc: tools/maketables.py | $(BUILD)
	python3 tools/maketables.py $@

# The demo song: a committed .smdj export (songs/demo.smdj) is baked
# in (its 16-byte SMDJ3 header stripped to the 5376-byte block, then
# expanded to the 6912-byte 52/40 layout via expanddemo.py); otherwise
# makedemo.py composes one. Remove songs/demo.smdj for the procedural demo.
ifneq ($(wildcard songs/demo.smdj),)
$(BUILD)/demo.bin: songs/demo.smdj tools/expanddemo.py | $(BUILD)
	tail -c +17 songs/demo.smdj | head -c 5376 | python3 tools/expanddemo.py > $@
# the 8 echo settings live in the SMDJ3 header's reserved area (+7)
$(BUILD)/demo_echo.bin: songs/demo.smdj | $(BUILD)
	tail -c +8 songs/demo.smdj | head -c 8 > $@
else
$(BUILD)/demo.bin: tools/makedemo.py tools/expanddemo.py | $(BUILD)
	python3 tools/makedemo.py $@.5376 && python3 tools/expanddemo.py < $@.5376 > $@
$(BUILD)/demo_echo.bin: | $(BUILD)
	head -c 8 /dev/zero > $@
endif

$(BUILD)/logo.inc: tools/makelogo.py art/smsggdj-logo.png | $(BUILD)
	python3 tools/makelogo.py art/smsggdj-logo.png $(BUILD)/logo.bin $@



# A pre-built pool (samples/pool.bin, e.g. exported from
# tools/patcher.html) is baked straight in; otherwise samples/*.wav
# are converted. Remove samples/pool.bin to go back to the WAVs.
ifneq ($(wildcard samples/pool.bin),)
$(BUILD)/pool.bin $(BUILD)/pool.inc: tools/smsggdj_sample.py samples/pool.bin | $(BUILD)
	python3 tools/smsggdj_sample.py --pool-in samples/pool.bin -o $(BUILD)/pool.bin --asm $(BUILD)/pool.inc
else
$(BUILD)/pool.bin $(BUILD)/pool.inc: tools/smsggdj_sample.py $(wildcard samples/*.wav) | $(BUILD)
	python3 tools/smsggdj_sample.py samples/*.wav -o $(BUILD)/pool.bin --asm $(BUILD)/pool.inc
endif

# Build stamp: short git hash (with a trailing + if the working tree has
# uncommitted changes), baked into the boot splash so a stale flash is obvious
# at a glance. Recomputed every build, but only rewritten (forcing a relink)
# when it actually changes.
BUILDID := $(shell h=$$(git rev-parse --short HEAD 2>/dev/null || echo nogit); git diff-index --quiet HEAD -- 2>/dev/null || h="$$h+"; printf '%s' "$$h" | tr 'a-z' 'A-Z')

$(BUILD)/buildid.inc: FORCE | $(BUILD)
	@printf '.BANK 1 SLOT 1\n.SECTION "BuildID" FREE\nstr_buildid: .db "%s", 0\n.ENDS\n' '$(BUILDID)' > $@.tmp
	@cmp -s $@.tmp $@ 2>/dev/null || mv -f $@.tmp $@
	@rm -f $@.tmp

SRCS := src/main.asm src/vdp.asm src/input.asm src/psg.asm src/engine.asm src/sample.asm src/editor.asm src/rle.asm
GEN  := $(BUILD)/font.bin $(BUILD)/demo.bin $(BUILD)/demo_echo.bin $(BUILD)/notes.inc $(BUILD)/pool.inc $(BUILD)/logo.inc $(BUILD)/buildid.inc

$(BUILD)/main.o: $(SRCS) $(GEN) | $(BUILD)
	$(ASM) -I $(BUILD) -o $@ src/main.asm

$(BUILD)/main-gg.o: $(SRCS) $(GEN) | $(BUILD)
	$(ASM) -D TARGET_GG=1 -I $(BUILD) -o $@ src/main.asm

$(BUILD)/linkfile: Makefile | $(BUILD)
	printf '[objects]\n$(BUILD)/main.o\n' > $@

$(BUILD)/linkfile-gg: Makefile | $(BUILD)
	printf '[objects]\n$(BUILD)/main-gg.o\n' > $@

$(ROM): $(BUILD)/main.o $(BUILD)/linkfile
	$(LINK) -v $(BUILD)/linkfile $@

$(GGROM): $(BUILD)/main-gg.o $(BUILD)/linkfile-gg
	$(LINK) -v $(BUILD)/linkfile-gg $@

# version-stamped copies (re-made whenever the canonical ROM changes; a release
# version bump in str_version yields a new filename automatically)
$(VROM): $(ROM)
	cp -f $< $@

$(VGGROM): $(GGROM)
	cp -f $< $@

JAVA := /opt/homebrew/opt/openjdk/bin/java
EMU  := tools/emulicious/Emulicious.jar

run: all                       # always rebuild both flavors
	$(JAVA) -jar $(EMU) $(abspath $(ROM))

run-gg: all
	$(JAVA) -jar $(EMU) $(abspath $(GGROM))

# build + print the version-stamped ROMs to attach to a GitHub release
dist: all
	@echo "release assets ($(VTAG)):"
	@echo "  $(VROM)"
	@echo "  $(VGGROM)"

clean:
	rm -rf $(BUILD)

FORCE:

.PHONY: all clean run run-gg dist FORCE

# codec self-test ROM: boots, round-trips rle_pack/rle_unpack on an embedded
# vector, shows RLE OK / RLE ERR on the splash. Zero cost in the normal build.
.PHONY: selftest
selftest: $(GEN) | $(BUILD)
	$(ASM) -D RLE_SELFTEST=1 -I $(BUILD) -o $(BUILD)/main-st.o src/main.asm
	{ echo '[objects]'; echo '$(BUILD)/main-st.o'; } > $(BUILD)/linkfile-st
	$(LINK) -v $(BUILD)/linkfile-st $(BUILD)/smsggdj-selftest.sms
	@echo built selftest ROM: $(BUILD)/smsggdj-selftest.sms

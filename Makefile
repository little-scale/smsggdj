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
# short git hash for the filename (with a trailing + for an uncommitted tree), so
# each *dev* build lands at a distinct name, e.g. build/smsggdj_v0_31_a1b2c3d.sms
# -- this is how we tell sub-incremental builds apart between releases. `make`
# emits these (plus the boot-splash build stamp) for exactly that.
GITHASH := $(shell h=$$(git rev-parse --short HEAD 2>/dev/null || echo nogit); git diff-index --quiet HEAD -- 2>/dev/null || h="$${h}+"; printf '%s' "$$h")
VROM   := $(BUILD)/smsggdj_$(VTAG)_$(GITHASH).sms
VGGROM := $(BUILD)/smsggdj_$(VTAG)_$(GITHASH).gg
# release assets carry the version ONLY (no hash): a tagged release is pinned to
# its version, so the filename is e.g. build/smsggdj_v0_36.sms. Made by `make dist`.
RELROM   := $(BUILD)/smsggdj_$(VTAG).sms
RELGGROM := $(BUILD)/smsggdj_$(VTAG).gg

all: $(ROM) $(GGROM) $(VROM) $(VGGROM)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/font.bin: tools/makefont.py | $(BUILD)
	python3 tools/makefont.py $@

$(BUILD)/notes.inc: tools/maketables.py | $(BUILD)
	python3 tools/maketables.py $@

$(BUILD)/logo.inc: tools/makelogo.py art/smsggdj-logo.png | $(BUILD)
	python3 tools/makelogo.py art/smsggdj-logo.png $(BUILD)/logo.bin $@



# Sample pool: built from the samples/ KIT FOLDERS (up to 8 kits x 8 samples), taken
# in alphanumeric order (kits = subfolders, samples = WAVs inside). The engine
# maps sample = kit*8 + (note mod 8). A pre-built pool (samples/pool.bin, e.g.
# exported from tools/patcher.html) still overrides if present.
# (The kit WAV paths contain spaces, so the rule depends on the samples/ tree
#  rather than listing files; run `make clean` after editing a WAV in place.)
ifneq ($(wildcard samples/pool.bin),)
$(BUILD)/pool.bin $(BUILD)/pool.inc: tools/smsggdj_sample.py samples/pool.bin | $(BUILD)
	python3 tools/smsggdj_sample.py --pool-in samples/pool.bin -o $(BUILD)/pool.bin --asm $(BUILD)/pool.inc
else
# SAMPLE_GAIN: post-normalize gain with hard clipping. Each sample is peak-
# normalized then driven SAMPLE_GAIN x (and clipped) for a louder/denser pool
# on the 4-bit log DAC. Override per build, e.g. `make SAMPLE_GAIN=4`.
SAMPLE_GAIN ?= 10
$(BUILD)/pool.bin $(BUILD)/pool.inc: tools/smsggdj_sample.py samples | $(BUILD)
	python3 tools/smsggdj_sample.py --kits samples --gain $(SAMPLE_GAIN) -o $(BUILD)/pool.bin --asm $(BUILD)/pool.inc
endif

# Build stamp: short git hash (with a trailing + if the working tree has
# uncommitted changes), baked into the boot splash so a stale flash is obvious
# at a glance. Recomputed every build, but only rewritten (forcing a relink)
# when it actually changes.
BUILDID := $(shell h=$$(git rev-parse --short HEAD 2>/dev/null || echo nogit); git diff-index --quiet HEAD -- 2>/dev/null || h="$$h+"; printf '%s' "$$h" | tr 'a-z' 'A-Z')

$(BUILD)/buildid.inc: FORCE | $(BUILD)
	@printf '.BANK 0 SLOT 0\n.SECTION "BuildID" FREE\nstr_buildid: .db "%s", 0\n.ENDS\n' '$(BUILDID)' > $@.tmp
	@cmp -s $@.tmp $@ 2>/dev/null || mv -f $@.tmp $@
	@rm -f $@.tmp

SRCS := src/main.asm src/vdp.asm src/input.asm src/psg.asm src/engine.asm src/sample.asm src/editor.asm src/rle.asm src/midi.asm
GEN  := $(BUILD)/font.bin $(BUILD)/notes.inc $(BUILD)/pool.inc $(BUILD)/logo.inc $(BUILD)/buildid.inc

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
	# .SMSTAG stamps an SMS Export region code ($4x) into the header at $7FFF;
	# the Game Gear needs a GG region code ($6x = GG Export) or the system /
	# flashcart auto-detect runs the ROM in SMS mode (margin + wrong palette).
	printf '\x6c' | dd of=$@ bs=1 seek=32767 conv=notrunc 2>/dev/null
	@test "$$(xxd -s 32767 -l 1 -p $@)" = "6c" || \
	  { echo "!! GG region stamp failed ($@ would run in SMS mode)"; rm -f $@; exit 1; }

# version-stamped copies (re-made whenever the canonical ROM changes; a release
# version bump in str_version yields a new filename automatically)
$(VROM): $(ROM)
	cp -f $< $@

$(VGGROM): $(GGROM)
	cp -f $< $@

# version-only copies for a tagged release (no git hash in the name)
$(RELROM): $(ROM)
	cp -f $< $@

$(RELGGROM): $(GGROM)
	cp -f $< $@

JAVA := /opt/homebrew/opt/openjdk/bin/java
EMU  := tools/emulicious/Emulicious.jar

run: all                       # always rebuild both flavors
	$(JAVA) -jar $(EMU) $(abspath $(ROM))

run-gg: all
	$(JAVA) -jar $(EMU) $(abspath $(GGROM))

# build + print the version-only ROMs to attach to a GitHub release
dist: all $(RELROM) $(RELGGROM)
	@echo "release assets ($(VTAG)):"
	@echo "  $(RELROM)"
	@echo "  $(RELGGROM)"

# format/tooling regression tests (no emulator): the SMDJ4 library self-test,
# the Z80-RLE mirror (asm pack logic vs the Python reference, SMDJ3 + SMDJ4
# block sizes), and syntax checks of the browser tools' scripts.
test:
	node tools/smdj4.js
	python3 tools/rle_z80mirror.py
	@for f in tools/*.js; do node --check $$f || exit 1; echo "syntax OK  $$f"; done
	@for f in tools/*.html; do \
	  awk '/<script>$$/{s=1;next} /<\/script>/{s=0} s' $$f > $(BUILD)/htmljs.tmp.js; \
	  if [ -s $(BUILD)/htmljs.tmp.js ]; then \
	    node --check $(BUILD)/htmljs.tmp.js || { echo "syntax FAIL $$f"; exit 1; }; \
	    echo "syntax OK  $$f (inline)"; \
	  fi; \
	done; rm -f $(BUILD)/htmljs.tmp.js

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

ASM   := wla-z80
LINK  := wlalink
BUILD := build
ROM   := $(BUILD)/smsdj.sms
GGROM := $(BUILD)/smsdj.gg

all: $(ROM) $(GGROM)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/font.bin: tools/makefont.py | $(BUILD)
	python3 tools/makefont.py $@

$(BUILD)/notes.inc: tools/maketables.py | $(BUILD)
	python3 tools/maketables.py $@

# The demo song: a committed .smdj export (songs/demo.smdj) is baked
# straight in (its 16-byte SMDJ3 header stripped, leaving the 5376-byte
# wave_ram..grooves block); otherwise makedemo.py composes one.
# Remove songs/demo.smdj to go back to the procedural demo.
ifneq ($(wildcard songs/demo.smdj),)
$(BUILD)/demo.bin: songs/demo.smdj | $(BUILD)
	tail -c +17 songs/demo.smdj | head -c 5376 > $@
# the 8 echo settings live in the SMDJ3 header's reserved area (+7)
$(BUILD)/demo_echo.bin: songs/demo.smdj | $(BUILD)
	tail -c +8 songs/demo.smdj | head -c 8 > $@
else
$(BUILD)/demo.bin: tools/makedemo.py | $(BUILD)
	python3 tools/makedemo.py $@
$(BUILD)/demo_echo.bin: | $(BUILD)
	head -c 8 /dev/zero > $@
endif

$(BUILD)/logo.inc: tools/makelogo.py art/smsggdj-logo.png | $(BUILD)
	python3 tools/makelogo.py art/smsggdj-logo.png $(BUILD)/logo.bin $@



# A pre-built pool (samples/pool.bin, e.g. exported from
# tools/patcher.html) is baked straight in; otherwise samples/*.wav
# are converted. Remove samples/pool.bin to go back to the WAVs.
ifneq ($(wildcard samples/pool.bin),)
$(BUILD)/pool.bin $(BUILD)/pool.inc: tools/smsdj_sample.py samples/pool.bin | $(BUILD)
	python3 tools/smsdj_sample.py --pool-in samples/pool.bin -o $(BUILD)/pool.bin --asm $(BUILD)/pool.inc
else
$(BUILD)/pool.bin $(BUILD)/pool.inc: tools/smsdj_sample.py $(wildcard samples/*.wav) | $(BUILD)
	python3 tools/smsdj_sample.py samples/*.wav -o $(BUILD)/pool.bin --asm $(BUILD)/pool.inc
endif

SRCS := src/main.asm src/vdp.asm src/input.asm src/psg.asm src/engine.asm src/sample.asm src/editor.asm
GEN  := $(BUILD)/font.bin $(BUILD)/demo.bin $(BUILD)/demo_echo.bin $(BUILD)/notes.inc $(BUILD)/pool.inc $(BUILD)/logo.inc

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

JAVA := /opt/homebrew/opt/openjdk/bin/java
EMU  := tools/emulicious/Emulicious.jar

run: all                       # always rebuild both flavors
	$(JAVA) -jar $(EMU) $(abspath $(ROM))

run-gg: all
	$(JAVA) -jar $(EMU) $(abspath $(GGROM))

clean:
	rm -rf $(BUILD)

.PHONY: all clean run run-gg

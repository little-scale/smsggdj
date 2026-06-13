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

$(BUILD)/demo.bin: tools/makedemo.py | $(BUILD)
	python3 tools/makedemo.py $@

$(BUILD)/logo.inc: tools/makelogo.py art/smsggdj-logo.png | $(BUILD)
	python3 tools/makelogo.py art/smsggdj-logo.png $(BUILD)/logo.bin $@



$(BUILD)/pool.bin $(BUILD)/pool.inc: tools/smsdj_sample.py $(wildcard samples/*.wav) | $(BUILD)
	python3 tools/smsdj_sample.py samples/*.wav -o $(BUILD)/pool.bin --asm $(BUILD)/pool.inc

$(BUILD)/main.o: src/main.asm src/vdp.asm src/input.asm src/psg.asm src/engine.asm src/sample.asm src/editor.asm $(BUILD)/font.bin $(BUILD)/demo.bin $(BUILD)/notes.inc $(BUILD)/pool.inc $(BUILD)/logo.inc | $(BUILD)
	$(ASM) -I $(BUILD) -o $@ src/main.asm

$(BUILD)/main-gg.o: src/main.asm src/vdp.asm src/input.asm src/psg.asm src/engine.asm src/sample.asm src/editor.asm $(BUILD)/font.bin $(BUILD)/demo.bin $(BUILD)/notes.inc $(BUILD)/pool.inc $(BUILD)/logo.inc | $(BUILD)
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

run: $(ROM)
	$(JAVA) -jar $(EMU) $(abspath $(ROM))

run-gg: $(GGROM)
	$(JAVA) -jar $(EMU) $(abspath $(GGROM))

clean:
	rm -rf $(BUILD)

.PHONY: all clean run run-gg

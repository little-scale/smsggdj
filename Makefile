ASM   := wla-z80
LINK  := wlalink
BUILD := build
ROM   := $(BUILD)/smsdj.sms

all: $(ROM)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/font.bin: tools/makefont.py | $(BUILD)
	python3 tools/makefont.py $@

$(BUILD)/notes.inc: tools/maketables.py | $(BUILD)
	python3 tools/maketables.py $@

$(BUILD)/main.o: src/main.asm src/vdp.asm src/input.asm src/psg.asm src/engine.asm src/editor.asm $(BUILD)/font.bin $(BUILD)/notes.inc | $(BUILD)
	$(ASM) -I $(BUILD) -o $@ src/main.asm

$(BUILD)/linkfile: Makefile | $(BUILD)
	printf '[objects]\n$(BUILD)/main.o\n' > $@

$(ROM): $(BUILD)/main.o $(BUILD)/linkfile
	$(LINK) -v $(BUILD)/linkfile $@

JAVA := /opt/homebrew/opt/openjdk/bin/java
EMU  := tools/emulicious/Emulicious.jar

run: $(ROM)
	$(JAVA) -jar $(EMU) $(abspath $(ROM))

clean:
	rm -rf $(BUILD)

.PHONY: all clean run

// Build 41: the keyboard experience (TEST, staging only; founder 2026-11-22,
// docs/briefs/dictation-keyboard-test.md, "Build 41"; branch agent/dictation-test, never merged).
// The shell checks (shell/MidasTests/DictationKeyboardBuild41Tests.swift) drive the pure logic; this
// file checks the wiring the simulator cannot: the build number, Apple's sounds and haptics in the
// keyboard's controller, no private calls added, Apple's 🎙 left on, and the Sidekick still offering
// keyboardMic "apple".
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

function shellFile(path: string): string {
  return readFileSync(new URL("../../shell/" + path, import.meta.url), "utf8");
}

const projectSource = shellFile("project.yml");
const experienceSource = shellFile("DictationKeyboardShared/DictationKeyboardExperience.swift");
const controllerSource = shellFile("MidasKeyboard/KeyboardViewController.swift");
const modelSource = shellFile("MidasKeyboard/MidasKeyboardModel.swift");
const numbersViewSource = shellFile("MidasKeyboard/MidasNumbersKeyboardView.swift");
const rootViewSource = shellFile("MidasKeyboard/MidasKeyboardView.swift");
const manifest = JSON.parse(readFileSync(new URL("../../sidekicks/dictation/manifest.json", import.meta.url), "utf8"));

function occurrences(text: string, needle: string): number {
  return text.split(needle).length - 1;
}

describe("dictation build 41: the build", () => {
  it("is build 41", () => {
    expect(projectSource).toContain('CURRENT_PROJECT_VERSION: "41"');
    expect(projectSource).not.toContain('CURRENT_PROJECT_VERSION: "40"');
  });
});

describe("dictation build 41: sounds and haptics", () => {
  it("the input view adopts UIInputViewAudioFeedback with input clicks on", () => {
    expect(controllerSource).toMatch(/class MidasKeyboardInputView: UIInputView, UIInputViewAudioFeedback/);
    expect(controllerSource).toMatch(/var enableInputClicksWhenVisible: Bool \{\s*true\s*\}/);
    expect(controllerSource).toContain("view = keyboardView");
  });

  it("plays Apple's system keyboard sounds per key kind, and the input click without Full Access", () => {
    expect(experienceSource).toMatch(/case \.character:\s*return 1104/);
    expect(experienceSource).toMatch(/case \.delete:\s*return 1155/);
    expect(experienceSource).toMatch(/case \.modifier:\s*return 1156/);
    expect(controllerSource).toContain("AudioServicesPlaySystemSound(SystemSoundID(soundID))");
    expect(controllerSource).toContain("UIDevice.current.playInputClick()");
  });

  it("a light haptic per key and a soft one for listening and landing, both prepared ahead", () => {
    expect(controllerSource).toContain("UIImpactFeedbackGenerator(style: .light)");
    expect(controllerSource).toContain("UIImpactFeedbackGenerator(style: .soft)");
    expect(occurrences(controllerSource, ".prepare()")).toBeGreaterThanOrEqual(4);
    expect(modelSource).toContain("playMoment(.listeningStarted)");
    expect(modelSource).toContain("playMoment(.textLanded)");
  });

  it("keys report touch down for the sound, and every backspace repeat plays the delete sound", () => {
    expect(numbersViewSource).toContain("onChange(of: configuration.isPressed");
    expect(numbersViewSource).toMatch(/keyboardModel\.keyPressed\(\.backspace\)\s*keyboardModel\.tap\(\.backspace\)/);
  });
});

describe("dictation build 41: the numbers-first keyboard", () => {
  it("is the keyboard only in keyboardMic apple; other modes keep build 40's", () => {
    expect(modelSource).toContain("usesNumbersLayout = isAppleMode");
    expect(rootViewSource).toMatch(/if model\.usesNumbersLayout \{\s*MidasNumbersKeyboard\(model: model\)/);
  });

  it("has a top bar with undo and, while Apple listens, Cancel", () => {
    expect(numbersViewSource).toContain('accessibility: "Undo"');
    expect(numbersViewSource).toContain('accessibility: "Cancel"');
    expect(numbersViewSource).toMatch(/if model\.showsCancel \{/);
  });

  it("respects Reduce Motion", () => {
    expect(numbersViewSource).toContain("@Environment(\\.accessibilityReduceMotion)");
    expect(numbersViewSource).toContain("DictationKeyboardMotion.forReduceMotion(reduceMotion)");
  });
});

describe("dictation build 41: public APIs only, Apple's 🎙 left on", () => {
  it("adds no private selector (the only one is still build 33's open URL)", () => {
    expect(occurrences(controllerSource, "NSSelectorFromString")).toBe(1);
    for (const source of [experienceSource, numbersViewSource, modelSource]) {
      expect(source).not.toContain("NSSelectorFromString");
      expect(source).not.toContain("value(forKey");
      expect(source).not.toContain("dlopen");
    }
  });

  it("never sets hasDictationKey, so iOS keeps drawing its 🎙", () => {
    expect(controllerSource).not.toMatch(/hasDictationKey\s*=/);
  });

  it("the Sidekick still offers keyboardMic apple", () => {
    const text = JSON.stringify(manifest);
    expect(text).toContain('"apple"');
    expect(text).toContain("keyboardMic");
  });
});

## Context

The Settings screen includes an Advanced git args sheet for running explicit
Git arguments through the repository abstraction. Today the text field opens
with `status` as editable content and also uses `status` as hint text. That
makes the sheet look like `git status` is already selected, even when the user
only opened the tool to type a different command.

## Goals / Non-Goals

**Goals:**

- Start Advanced git args with an empty argument input.
- Show example commands as dim placeholder text rather than editable content.
- Ensure placeholder examples are never treated as command input.
- Keep existing argument parsing, shell-syntax validation, command execution,
  output rendering, and error handling.

**Non-Goals:**

- Changing bridge/core Git execution APIs.
- Adding command history, autocomplete, or a command picker.
- Changing standard Git buttons such as status, pull, push, or commit.

## Decisions

- Use an empty local `argsText` value when the sheet opens.
  - Rationale: this is the smallest behavioral change and removes the false
    impression that `git status` is preselected.
  - Alternative considered: keep `status` as initial text but select it for
    replacement. This still leaves an executable default value and does not
    match the requested hint-only behavior.

- Put examples in the text field decoration, e.g. `status, log`.
  - Rationale: placeholder text is visually dim by platform convention and
    communicates examples without becoming input.
  - Alternative considered: add an explanatory sentence below the input. That
    is more verbose and less directly tied to the field.

- Keep the existing blank-input validation path.
  - Rationale: users must type actual arguments before running; the
    implementation can continue to show the existing "enter arguments" error
    if Run is pressed while empty.
  - Alternative considered: disable the Run button until input is non-empty.
    That is also acceptable, but preserving validation avoids changing the
    button interaction contract more than needed.

## Risks / Trade-offs

- Existing tests that expect `git status` immediately after opening the sheet
  will need to be updated to assert the hint-only behavior.
- Placeholder rendering can be awkward to assert directly in widget tests, so
  tests should also verify the field's actual text is empty and `git status`
  is not shown as the selected command before typing.

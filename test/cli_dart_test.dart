// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'utils.dart';

void main() {
  ensureExecutableUpToDate();

  test("--version prints the migrator version", () async {
    var migrator = await runMigrator(["--version"]);
    expect(migrator.stdout, emits(matches(RegExp(r"^\d+\.\d+\.\d+"))));
    await migrator.shouldExit(0);
  });

  test("--help prints the usage documentation", () async {
    // Checking the entire output is brittle, so just do a sanity check to make
    // sure it's not totally busted.
    var migrator = await runMigrator(["--help"]);
    expect(
        migrator.stdout, emits("Migrates stylesheets to new Sass versions."));
    expect(migrator.stdout,
        emitsThrough(contains("Print this usage information.")));
    await migrator.shouldExit(0);
  });

  group("with --dry-run", () {
    test("prints the name of a file that would be migrated", () async {
      await d.file("test.scss", "a {b: abs(-1)}").create();

      var migrator = await runMigrator(["--dry-run", "module", "test.scss"]);
      expect(
          migrator.stdout,
          emitsInOrder([
            "Dry run. Logging migrated files instead of overwriting...",
            "",
            "test.scss",
            emitsDone
          ]));
      await migrator.shouldExit(0);
    });

    test("doesn't print the name of a file that doesn't need to be migrated",
        () async {
      await d.file("test.scss", "a {b: abs(-1)}").create();
      await d.file("other.scss", "a {b: c}").create();

      var migrator =
          await runMigrator(["--dry-run", "module", "test.scss", "other.scss"]);
      expect(
          migrator.stdout,
          emitsInOrder([
            "Dry run. Logging migrated files instead of overwriting...",
            "",
            "test.scss",
            emitsDone
          ]));
      await migrator.shouldExit(0);
    });

    test("doesn't print the name of imported files without --migrate-deps",
        () async {
      await d.file("test.scss", "@import 'other'").create();
      await d.file("_other.scss", "a {b: abs(-1)}").create();

      var migrator = await runMigrator(["--dry-run", "module", "test.scss"]);
      expect(
          migrator.stdout,
          emitsInOrder([
            "Dry run. Logging migrated files instead of overwriting...",
            "",
            "test.scss",
            emitsDone
          ]));
      await migrator.shouldExit(0);
    });

    test("prints the name of imported files with --migrate-deps", () async {
      await d.file("test.scss", "@import 'other'").create();
      await d.file("_other.scss", "a {b: abs(-1)}").create();

      var migrator = await runMigrator(
          ["--dry-run", "--migrate-deps", "module", "test.scss"]);
      expect(
          migrator.stdout,
          emitsInOrder([
            "Dry run. Logging migrated files instead of overwriting...",
            "",
            emitsInAnyOrder(["test.scss", "_other.scss"]),
            emitsDone
          ]));
      await migrator.shouldExit(0);
    });

    test("prints the contents of migrated files with --verbose", () async {
      await d.file("test.scss", "@import 'other'").create();
      await d.file("_other.scss", "a {b: abs(-1)}").create();

      var migrator = await runMigrator(
          ["--dry-run", "--migrate-deps", "--verbose", "module", "test.scss"]);
      expect(
          migrator.stdout,
          emitsInOrder([
            "Dry run. Logging migrated files instead of overwriting...",
            "",
            emitsInAnyOrder([
              emitsInOrder(["<===> test.scss", "@use 'other'"]),
              emitsInOrder([
                "<===> _other.scss",
                '@use "sass:math";',
                "a {b: math.abs(-1)}"
              ]),
            ]),
            emitsDone
          ]));
      await migrator.shouldExit(0);
    });
  });

  group("gracefully handles", () {
    test("an unknown command", () async {
      var migrator = await runMigrator(["asdf"]);
      expect(migrator.stderr, emits('Could not find a command named "asdf".'));
      expect(migrator.stderr,
          emitsThrough(contains('for more information about a command.')));
      await migrator.shouldExit(64);
    });

    test("an unknown argument", () async {
      var migrator = await runMigrator(["--asdf"]);
      expect(migrator.stderr, emits('Could not find an option named "asdf".'));
      expect(migrator.stderr,
          emitsThrough(contains('for more information about a command.')));
      await migrator.shouldExit(64);
    });

    test("a syntax error", () async {
      await d.file("test.scss", "a {b: }").create();

      var migrator = await runMigrator(["--no-unicode", "module", "test.scss"]);
      expect(
          migrator.stderr,
          emitsInOrder([
            "Error: Expected expression.",
            "  ,",
            "1 | a {b: }",
            "  |       ^",
            "  '",
            "  test.scss 1:7  root stylesheet"
          ]));
      await migrator.shouldExit(1);
    });

    test("an error from a migrator", () async {
      await d.file("test.scss", "@import 'nonexistent';").create();

      var migrator = await runMigrator(["--no-unicode", "module", "test.scss"]);
      expect(
          migrator.stderr,
          emitsInOrder([
            "Error: Could not find Sass file at 'nonexistent'.",
            "  ,",
            "1 | @import 'nonexistent';",
            "  |         ^^^^^^^^^^^^^",
            "  '",
            "  test.scss 1:9  root stylesheet",
            "Migration failed!"
          ]));
      await migrator.shouldExit(1);
    });

    group("and colorizes with --color", () {
      test("a syntax error", () async {
        await d.file("test.scss", "a {b: }").create();

        var migrator = await runMigrator(
            ["--no-unicode", "--color", "module", "test.scss"]);
        expect(
            migrator.stderr,
            emitsInOrder([
              "Error: Expected expression.",
              "\u001b[34m  ,\u001b[0m",
              "\u001b[34m1 |\u001b[0m a {b: \u001b[31m\u001b[0m}",
              "\u001b[34m  |\u001b[0m       \u001b[31m^\u001b[0m",
              "\u001b[34m  '\u001b[0m",
              "  test.scss 1:7  root stylesheet",
            ]));
        await migrator.shouldExit(1);
      });

      test("an error from a migrator", () async {
        await d.file("test.scss", "@import 'nonexistent';").create();

        var migrator = await runMigrator(
            ["--no-unicode", "--color", "module", "test.scss"]);
        expect(
            migrator.stderr,
            emitsInOrder([
              "Error: Could not find Sass file at 'nonexistent'.",
              "\u001b[34m  ,\u001b[0m",
              "\u001b[34m1 |\u001b[0m @import \u001b[31m'nonexistent'\u001b[0m;",
              "\u001b[34m  |\u001b[0m         \u001b[31m^^^^^^^^^^^^^\u001b[0m",
              "\u001b[34m  '\u001b[0m",
              "  test.scss 1:9  root stylesheet",
              "Migration failed!"
            ]));
        await migrator.shouldExit(1);
      });
    });
  });
}
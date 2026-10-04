# Release notes

One folder per version, named after `MARKETING_VERSION` in `project.yml`:

```
release-notes/1.0.0/en.html
release-notes/1.0.0/zh-Hans.html
release-notes/1.0.0/ja.html
```

Each file is a short HTML fragment, not a full page, for example:

```html
<ul>
  <li>Ctrl+Backspace deletes a word again in fn mode.</li>
  <li>The clipboard history opens where the pointer is.</li>
</ul>
```

`scripts/publish-release.sh` puts all three into the update feed (`site/appcast.xml`), and
KeyBridge's update window shows the one in the app's language. The English file is also the
body of the GitHub release. The script refuses to publish while any of the three is missing
or empty.

KeyBridge itself speaks ten languages, but the notes are written in these three. Sparkle picks
the one closest to the user's languages and falls back to the first, English, so a German or
Korean user reads the English notes.

Write for the people using KeyBridge, not for contributors: what changed for them, in plain
words, most noticeable first. Leave out refactors and tests.

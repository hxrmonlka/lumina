<h1 align=center>
. ݁₊ ⊹ . ݁ Lumina݁ ݁ . ⊹ ₊ ݁.
</h1>

<h4 align=center>
The library, packager, and CLI of Alice.
</h4>

<details><summary><b>Why is it specifically designed to be a three-in-one?</b></summary>
It is something I personally use. Plus, I feel like it's efficient, in a way. I don't have to manage multiple repositories at once for something that does all three.
</details>
<details><summary><b>How does this work?</b></summary>
<ul>
<li>Lumina as a library, is <i>consumed</i> by Alice using <a href="https://wiki.nixos.org/wiki/Flakes">Nix Flakes</a>.</li>
<li>Lumina can also be the one that packages things for Alice (it also gets updates), for example: <code>inputs.lumina.packages.${system}.package-name</code></li>
<li>And, as for Lumina as a CLI, it can do simple things, like syncing settings for Alice. (e.g. <code>lumina sync settings/dms</code>)</li>
<p>Commands may vary depending on which system configuration is being used. (That's right, CLI is mostly unusable for other people's systems.)</p>
</ul>
</details>

---

### Contents

| Role     | Outputs                                                                                     |
| -------- | ------------------------------------------------------------------------------------------- |
| Library  | `lib.*`, `overlays.default`, `nixosModules.signature`, `homeModules.signature`.             |
| Packager | `packages.${system}.*`. (e.g. `yazi-plugins`, `spicetify-live-apply`, `helium-extensions`). |
| CLI      | the `lumina` command.                                                                       |
### Usage
Requirements: Nix with flakes enabled.
Add Lumina as an input in Alice:
```nix
inputs.lumina.url = "github:hxrmonlka/lumina/un/test";
```
Alice pins Lumina by commit. After every push to Lumina, run this in Alice:
```sh
nix flake update lumina
```
Alice lives at [hxrmonlka/alice](https://github.com/hxrmonlka/alice) (branch `test-den`).
### CLI
Targets use a `category/name` format, like Gentoo!
```sh
lumina sync settings/dms
lumina sync settings/dms-kdl
lumina sync settings/noctalia
lumina sync settings/noctalia-kdl
```
Some targets work only on specific hosts. On any other host, the command stops with an error since... you know, like I said.
To tell Lumina where the local Alice copy is, set `ALICE_DOTFILES` or pass the path:
```sh
lumina sync --loc /path/to/alice
```

Alice options:
```nix
programs.lumina-cli.enable = true;
programs.lumina-cli.configPath = "/path/to/alice";
```
### Branches
Relatively similar to how Alice's branches work, but there is no ground for collaboration, *yet*.
`un/test` does a squash & merge to `main` whenever I feel like it.
### Planned work
- Performance tuning modules for Intel, AMD, and Nvidia hardware.
- Some random library for Bedrock.

> [!WARNING]
> This project is still in development, so is the README and the Wiki.
# Avisos de terceiros

O Ember é software livre sob a [GPL-3.0-or-later](LICENSE). Ele usa os componentes abaixo, cada um com a sua licença. Os textos completos aparecem no app, em **Ajustes › Sobre › Licenças de código aberto**.

## Motor

O Ember contém uma **versão modificada** do mkxp-z-apple-mobile. As modificações ficam em [`engine-patches/`](engine-patches) e são aplicadas por [`scripts/patch-engine.sh`](scripts/patch-engine.sh).

> mkxp-z-apple-mobile, Copyright (C) 2026 Mateo M., https://github.com/mateo-m/mkxp-z-apple-mobile

O mkxp-z-apple-mobile é distribuído sob a GPL-3.0 com termos adicionais (seção 7): atribuição, origem e uso de nomes. Veja o `ADDITIONAL-TERMS.md` do repositório do motor. Ele é baseado no mkxp-z e no mkxp:

> mkxp-z, Copyright (C) 2013-2023 Jonas Kulla and contributors. GPL-2.0-or-later.

O motor traz as próprias dependências, listadas com licença no `licenses/manifest.json` dele. Entre elas: Ruby 1.8, 1.9 e 3.1 (Ruby License / BSD-2-Clause), SDL2, SDL2_image, SDL2_ttf e SDL2_sound (zlib), OpenAL Soft (LGPL-2.0-or-later), ANGLE (BSD-3-Clause), PhysicsFS (zlib), FreeType (FTL), libogg, libvorbis e libtheora (BSD-3-Clause), pixman (MIT), uchardet (MPL-1.1 / GPL-2.0 / LGPL-2.1), OpenSSL (Apache-2.0), fontes Liberation (OFL-1.1) e WenQuanYi Micro Hei (Apache-2.0).

## Componentes do app

| Componente | Licença | Como entra |
| --- | --- | --- |
| [FluidSynth](https://github.com/FluidSynth/fluidsynth) 2.5.7 | LGPL-2.1-or-later | Biblioteca estática para tocar MIDI. Compilada por `scripts/build-fluidsynth.sh`, que muda um padrão (`synth.dynamic-sample-loading` ligado). |
| [GeneralUser GS](https://github.com/mrbumpy409/GeneralUser-GS) v2.0.3, de S. Christian Collins | GeneralUser GS License v2.0 | Banco de instrumentos MIDI. Fica fora do repositório e é copiado para o app no build. |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | MIT | Pacote Swift para abrir .zip. |
| libarchive (a do iOS) | BSD-2-Clause | Biblioteca do sistema, para .rar, .7z e .exe autoextraível. Só os cabeçalhos estão em `Ember/Vendor/libarchive`. |

O FluidSynth e o OpenAL Soft são LGPL e ficam ligados estaticamente. Como o Ember inteiro é GPL e o código-fonte está aqui, dá para recompilar o app com outras versões dessas bibliotecas, como a LGPL pede.

## Marcas e conteúdo

- RPG Maker é marca registrada dos respectivos donos. O Ember não tem relação com eles nem é endossado por eles.
- O Ember não inclui nenhum jogo nem o RTP do RPG Maker. Você importa os seus.
- Os nomes "Mateo M." e "Grid" não são usados para divulgar o Ember. A atribuição acima é exigida pela licença do motor.

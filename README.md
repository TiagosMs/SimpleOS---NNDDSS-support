<p align="center">
  <img src="docs/images/logo.png" alt="SimpleOS for Anbernic RG DS" width="720">
</p>

# SimpleOS — NNDDSS Support & Quick Stock Switch Edition

Fork customizado do [SimpleOS oficial](https://github.com/boorngos/SimpleOS) por **[TiagosMs](https://github.com/TiagosMs)** para o console portátil **[Anbernic RG DS](https://anbernic.com/)**.

Esta edição inclui **suporte nativo e automático ao emulador NNDDSS** e um **atalho de troca rápida para o sistema original Anbernic**, direto pelo carrossel de jogos do SimpleOS.

---

## 🌟 O que há de novo neste Fork? (Novidades & Modificações)

### 1. 🚀 Suporte Integrado ao Emulador NNDDSS
- O emulador **NNDDSS** (v1.0.1 Stable) já vem embutido no instalador do SimpleOS.
- Ao rodar a instalação do SimpleOS, o NNDDSS é automaticamente instalado em `/mnt/vendor/deep/nnddss` e configurado no cartão SD.
- Um gatilho chamado **`NNDDSS EMUL`** aparece na sua lista de jogos. Ao selecioná-lo:
  - O emulador NNDDSS abre diretamente com todos os seus recursos, renderização nativa e shaders.
  - Ao sair do NNDDSS, o console **retorna automaticamente para a interface do SimpleOS**.

### 2. 🔄 Retorno Rápido ao Sistema Original (`Voltar Stock`)
- Chega de ter que plugar o cartão no PC para criar arquivos manuais: o carrossel agora possui o card **`VOLTAR STOCK`**.
- Ao clicar nele:
  - O console aplica a flag de retorno e reinicia imediatamente no sistema padrão da Anbernic, liberando todas as outras plataformas (GBA, SNES, PS1, etc.), vídeos e APPS.
  - Para voltar ao SimpleOS depois: basta abrir **Applications** → **APPS** → **`SimpleOS`**.

### 3. ⚙️ Script `run.sh` e `loop.sh` Otimizados
- O despachante do SimpleOS ([`run.sh`](simpleos/system/run.sh)) foi reprogramado para interceptar comandos especiais antes do DraStic.
- O gerenciador de loop ([`loop.sh`](simpleos/system/loop.sh)) agora monitora os processos tanto do DraStic quanto do NNDDSS, garantindo transições limpas sem travar o Wayland.

---

## 📥 Como Instalar

1. Baixe o pacote `.zip` da release desta versão.
2. No seu computador, abra a partição **ROMS** do cartão SD do RG DS (onde ficam as pastas `Roms/`, `Emu/`, etc.).
3. Extraia o conteúdo do zip diretamente na raiz dessa partição (se o sistema pedir para mesclar pastas, confirme).
4. Ejete o cartão com segurança e ligue o console.
5. No menu oficial da Anbernic, vá em: **Applications** → **APPS** → selecione **`Install SimpleOS`**.
6. Aguarde as telas de splash em ambos os visores terminarem.
7. O console reiniciará automaticamente no **SimpleOS** com o **NNDDSS** e o atalho **Voltar Stock** prontos para uso!

---

## 🎮 Controles no SimpleOS

| Ação | Comando |
| :--- | :--- |
| Abrir / Fechar menu in-game | **Home / Back (Menu)** |
| Navegar no menu | **D-Pad Esquerda / Direita** |
| Avanço rápido (Fast-Forward) | **Anbernic** + **SELECT** |
| Salvar / Carregar State | **Anbernic** + **L2** / **R2** |
| Microfone virtual | **R3** (clique do analógico direito) |
| Alternar contador de FPS | **Anbernic** + **X** |
| Controle de Brilho | **Anbernic** + **L1** (diminui) / **R1** (aumenta) |
| Modo noturno (Night Mode) | Abaixo do nível mínimo de brilho |
| Suspender (Sleep) | Toque rápido no botão **POWER** ou feche a tampa |
| Desligar console | Segure o botão **POWER** |

---

## 📜 Créditos e Licença

- **[boorngos](https://github.com/boorngos/SimpleOS)** — Criador do SimpleOS original para o RG DS.
- **[TiagosMs](https://github.com/TiagosMs)** — Customização, integração do NNDDSS e sistema de retorno ao Stock OS.
- Comunidade NNDDSS RG DS — Pelos patches estáveis e wrappers do NNDDSS.
- Licença: **MIT License**. Veja o arquivo [LICENSE](LICENSE) para mais detalhes.

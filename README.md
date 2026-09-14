# sm4-itercore — SM4 迭代加解密核

国密 **SM4**（GB/T 32907 / GM/T 0002）128-bit 分组 / 128-bit 密钥，**迭代 32 轮**可综合 Verilog，配套 MMIO 与 Icarus 自检 TB。

与 [rv32i-cryptocore](https://github.com/beginnerof/rv32i-cryptocore)（AES-128）工程风格对齐，可作为 SoC 第二个安全协处理器。

> 仿真结果：`tb_sm4` 输出 **PASS（9 checks）**  
> 标准向量 1（GM/T 0002）加密/解密 + 自生成向量 2 加密/解密均通过。

## English Abstract

A synthesizable **iterative SM4** encrypt/decrypt core (GB/T 32907), 128-bit block/key, 32 rounds. One round is reused after a 32-cycle key expansion; decrypt uses the same datapath with reversed round keys. A word-oriented MMIO wrapper matches the AES cryptocore register map. Self-checking Icarus TB programs the GM/T 0002 sample and a second vector through MMIO — encrypt and decrypt both `PASS`.

### Resume bullets

1. Implemented an iterative SM4 core (32-round, shared enc/dec datapath, reversed rk for decrypt); GM/T 0002 vector + second vector encrypt/decrypt **PASS** under Icarus.
2. Exposed SM4 through an AES-compatible MMIO map (CTRL/STATUS/KEY/DIN/DOUT/VERSION) for SoC integration.
3. Kept a Python reference (`scripts/sm4_ref.py`) used to generate CK tables and validate RTL vectors.

---

## 架构

```text
Host (CPU / TB)
    | 32-bit MMIO
    v
sm4_mmio   CTRL/STATUS/KEY/DIN/DOUT
    |
    v
sm4_core   KEY_EXP (32 cyc) → ROUND x32 → reverse out
    |
    v
S-box τ  +  L / L'  线性变换
```

延迟约 **65+ 拍 / 块**（密钥扩展 32 + 数据轮 32）。面积优先的迭代结构，不是全展开高吞吐版。

## 寄存器图（与 AES 仓兼容）

| 偏移 | 名称 | 属性 | 说明 |
|------|------|------|------|
| 0x00 | CTRL | WO | [0] start（自清）[1] decrypt |
| 0x04 | STATUS | RW | [0] busy [1] done（写 1 清） |
| 0x08..0x14 | KEY0..3 | RW | KEY0 = 密钥高 32 位 |
| 0x18..0x24 | DIN0..3 | RW | 明文/密文输入 |
| 0x28..0x34 | DOUT0..3 | RO | 结果 |
| 0x38 | VERSION | RO | `0x0002_0000` |

## 快速开始

```bash
# 软件参考模型（标准向量）
python scripts/sm4_ref.py
# PASS

# RTL
make test
# PASS  (9 checks)
```

Windows + 本机 Icarus：

```powershell
cd sm4-itercore
New-Item -ItemType Directory -Force sim | Out-Null
iverilog -g2001 -o sim\tb_sm4.vvp rtl\sm4_core.v rtl\sm4_mmio.v rtl\sm4_top.v tb\tb_sm4.v
cd sim; vvp tb_sm4.vvp
```

## 标准向量

| | Key | Plain | Cipher |
|--|-----|-------|--------|
| V1 (GM/T 0002) | `0123456789abcdeffedcba9876543210` | 同左 | `681edf34d206965e86b3e94f536e4246` |
| V2 | 同 V1 | `fedcba98765432100123456789abcdef` | `f0a2b07e64dd2c2590f93e4edd90fbb4` |

## 设计取舍

- **迭代而非全展开**：小面积、约 32+ 拍完成一轮密钥扩展 + 32 数据轮；适合挂 SoC 的低频安全外设
- **加解密共用**：解密 = 加密 + `rk` 逆序，不复制轮函数
- **L / L' 分离**：数据通路 L（rot 2/10/18/24），密钥扩展 L'（rot 13/23）
- **无侧信道防护**：功能正确性优先；DPA/故障注入不在本仓范围
- **字节序**：128-bit 字大端（与 FIPS/GM 样例及 AES 仓一致）

## 面试可能问的点

1. 迭代 vs 全展开：面积/吞吐/延迟折中  
2. 为什么解密能复用加密硬件  
3. S 盒实现（查找表 vs 布尔式）  
4. SM4 与 AES 轮结构差异  
5. 如何验证正确性（标准向量 + 参考模型）  
6. 侧信道：本实现只保证功能，不抗 DPA  

## 目录

```text
rtl/      sm4_sbox.v sm4_core.v sm4_mmio.v sm4_top.v
tb/       tb_sm4.v
scripts/  sm4_ref.py
sim/      仿真产物
Makefile
```

## 后续（作品集可选）

- [x] 挂到 `rv32i-minisoc`（`0x1000_0080`），CPU 汇编驱动，GM/T 0002 加解密回读 `PASS`
- [x] LibreLane / sky130 RTL→GDS（见 [sm4-asic-flow-lab](https://github.com/beginnerof/sm4-asic-flow-lab)）：**0.343 mm² / 70k cells / timing clean / 0 DRC** @ 25 MHz
- [ ] 更高频率重跑（setup slack 仍有约 5 ns 余量）

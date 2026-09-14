# SM4 验证计划

DUT：`sm4_top`（`sm4_mmio` + `sm4_core`）  
工具：Icarus Verilog（无 license）  
参考：`scripts/sm4_ref.py`

## 测试点

| ID | 验证点 | 方式 | 状态 |
|----|--------|------|------|
| SM4-1 | 复位后 VERSION=`0x00020000` | MMIO 读 | HIT |
| SM4-2 | GM/T 0002 标准向量加密 | KEY/DIN → start → DOUT | HIT |
| SM4-3 | 同向量解密回读 | decrypt 位 + 同 KEY | HIT |
| SM4-4 | 第二组明文加密/解密 | 自生成（ref 背书） | HIT |
| SM4-5 | done 握手 / W1C | STATUS poll | HIT |

## 实测（2026-09）

```text
tool:   Icarus Verilog
result: PASS  (9 checks)
V1 CT:  681edf34d206965e86b3e94f536e4246  (GM/T 0002)
V2 CT:  f0a2b07e64dd2c2590f93e4edd90fbb4
```

## 与 UVM 的关系

本仓先做 **Icarus 可复现闭环**。若后续加 UVM，可复用 `axi4lite-regip/uvm` 的 agent 形态，或做简单 bus-functional MMIO sequence；优先级低于挂 SoC / ASIC 流程。

## DoD

- [x] Python ref 与标准向量一致  
- [x] RTL 加解密两向量 PASS  
- [x] MMIO 寄存器图与 AES 仓兼容  
- [ ] （可选）挂 minisoc  
- [ ] （可选）RTL→GDS  

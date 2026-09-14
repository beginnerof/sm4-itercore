# sm4-itercore — Icarus flow
#   make test

IVERILOG ?= iverilog
VVP      ?= vvp

RTL = rtl/sm4_core.v rtl/sm4_mmio.v rtl/sm4_top.v

.PHONY: test ref clean

all: test

ref:
	python scripts/sm4_ref.py

test: sim/tb_sm4.vvp
	cd sim && $(VVP) tb_sm4.vvp

sim/tb_sm4.vvp: $(RTL) tb/tb_sm4.v
	@mkdir -p sim 2>/dev/null || mkdir sim 2>NUL || exit 0
	$(IVERILOG) -g2001 -o sim/tb_sm4.vvp $(RTL) tb/tb_sm4.v

clean:
	rm -rf sim/*.vvp sim/*.vcd 2>/dev/null || powershell -c "Remove-Item -Force sim\* -ErrorAction SilentlyContinue"

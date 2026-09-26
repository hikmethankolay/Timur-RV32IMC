#!/usr/bin/env python3
"""Vector files for the Phase 10 unit testbenches, from reference models.

Writes, relative to the project root (run it from there):
  vectors/csr_file_vectors.txt    tb/csr_file_tb.v
  vectors/trap_unit_vectors.txt   tb/trap_unit_tb.v

The models below follow the RISC-V privileged specification and the CSR set
of the build guide; they are written independently of the RTL, so a mistake
has to be made twice to go unnoticed. Random sections use a fixed seed, so the
files are reproducible.

Usage:  python3 sw/gen_unit_vectors.py
"""

import random

MASK = 0xFFFFFFFF
SEED = 20260927

# ---------------------------------------------------------------------------
# CSR file
# ---------------------------------------------------------------------------
MSTATUS, MISA, MIE, MTVEC, MSCRATCH, MEPC, MCAUSE, MTVAL, MIP = (
    0x300, 0x301, 0x304, 0x305, 0x340, 0x341, 0x342, 0x343, 0x344)
MCYCLE, MINSTRET, MCYCLEH, MINSTRETH = 0xB00, 0xB02, 0xB80, 0xB82
CYCLE, TIME, INSTRET, CYCLEH, TIMEH, INSTRETH = 0xC00, 0xC01, 0xC02, 0xC80, 0xC81, 0xC82
IDS = (0xF11, 0xF12, 0xF13, 0xF14)
IMPLEMENTED = {MSTATUS, MISA, MIE, MTVEC, MSCRATCH, MEPC, MCAUSE, MTVAL, MIP, MCYCLE, MINSTRET,
               MCYCLEH, MINSTRETH, CYCLE, TIME, INSTRET, CYCLEH, TIMEH, INSTRETH} | set(IDS)
MISA_VALUE = 0x40001104
WRITE, SET, CLEAR = 0, 1, 2


class CsrModel:
    def __init__(self):
        self.reset()

    def reset(self):
        self.mie = self.mpie = self.meie = 0
        self.mtvec = self.mscratch = self.mepc = self.mcause = self.mtval = 0
        self.mcycle = self.minstret = 0

    def read(self, addr, irq):
        meip = int(irq != 0)
        values = {
            MSTATUS: (3 << 11) | (self.mpie << 7) | (self.mie << 3),
            MISA: MISA_VALUE,
            MIE: self.meie << 11,
            MTVEC: self.mtvec,
            MSCRATCH: self.mscratch,
            MEPC: self.mepc,
            MCAUSE: self.mcause,
            MTVAL: self.mtval,
            MIP: meip << 11,
            MCYCLE: self.mcycle & MASK, CYCLE: self.mcycle & MASK, TIME: self.mcycle & MASK,
            MCYCLEH: self.mcycle >> 32, CYCLEH: self.mcycle >> 32, TIMEH: self.mcycle >> 32,
            MINSTRET: self.minstret & MASK, INSTRET: self.minstret & MASK,
            MINSTRETH: self.minstret >> 32, INSTRETH: self.minstret >> 32,
        }
        for a in IDS:
            values[a] = 0
        return values.get(addr, 0)

    def outputs(self, v):
        """Combinational outputs for the inputs of vector v."""
        rdata = self.read(v["addr"], v["irq"])
        illegal = int(v["addr"] not in IMPLEMENTED or (v["attempt"] and (v["addr"] >> 10) == 3))
        irq_pending = int(self.mie and self.meie and v["irq"] != 0)
        return rdata, illegal, self.mtvec, self.mepc, irq_pending

    def clock(self, v):
        if not v["rst_n"]:
            self.reset()
            return
        old = self.read(v["addr"], v["irq"])
        new = {WRITE: v["wdata"], SET: old | v["wdata"], CLEAR: old & ~v["wdata"] & MASK}.get(v["op"], v["wdata"])
        a, we = v["addr"], v["we"]
        if v["trap"]:
            self.mepc = v["epc"] & ~1 & MASK
            self.mcause, self.mtval = v["cause"], v["val"]
            self.mpie, self.mie = self.mie, 0
        elif v["mret"]:
            self.mie, self.mpie = self.mpie, 1
        elif we:
            if a == MSTATUS:
                self.mie, self.mpie = (new >> 3) & 1, (new >> 7) & 1
            elif a == MIE:
                self.meie = (new >> 11) & 1
            elif a == MTVEC:
                self.mtvec = new & ~3 & MASK
            elif a == MSCRATCH:
                self.mscratch = new
            elif a == MEPC:
                self.mepc = new & ~1 & MASK
            elif a == MCAUSE:
                self.mcause = new
            elif a == MTVAL:
                self.mtval = new
        if we and a in (MCYCLE, MCYCLEH):
            self.mcycle = ((self.mcycle >> 32) << 32 | new) if a == MCYCLE else (new << 32 | (self.mcycle & MASK))
        else:
            self.mcycle = (self.mcycle + 1) & ((1 << 64) - 1)
        if we and a in (MINSTRET, MINSTRETH):
            self.minstret = ((self.minstret >> 32) << 32 | new) if a == MINSTRET else (new << 32 | (self.minstret & MASK))
        elif v["retire"]:
            self.minstret = (self.minstret + 1) & ((1 << 64) - 1)


def csr_vector(**kw):
    v = dict(rst_n=1, addr=0, op=WRITE, wdata=0, attempt=0, we=0, trap=0, cause=0, epc=0, val=0,
             mret=0, retire=0, irq=0)
    v.update(kw)
    return v


def csr_vectors():
    m = CsrModel()
    lines = []

    def cycle(comment=None, **kw):
        v = csr_vector(**kw)
        if comment:
            lines.append("// " + comment)
        ins = "%d %03X %d%d %08X %d %d %d %08X %08X %08X %d %d %d%d" % (
            v["rst_n"], v["addr"], v["op"] >> 1, v["op"] & 1, v["wdata"], v["attempt"], v["we"],
            v["trap"], v["cause"], v["epc"], v["val"], v["mret"], v["retire"], v["irq"] >> 1, v["irq"] & 1)
        if v["rst_n"]:
            rdata, illegal, mtvec, mepc, irqp = m.outputs(v)
            lines.append("%s  %08X %d %08X %08X %d 0" % (ins, rdata, illegal, mtvec, mepc, irqp))
        else:
            lines.append("%s  xxxxxxxx x xxxxxxxx xxxxxxxx x 0" % ins)
        m.clock(v)
        lines.append("%s  xxxxxxxx x xxxxxxxx xxxxxxxx x 1" % ins)

    def read(addr, comment=None, irq=0):
        cycle(comment, addr=addr, irq=irq)

    def write(addr, value, op=WRITE, comment=None, we=1):
        cycle(comment, addr=addr, op=op, wdata=value, attempt=1, we=we)

    cycle("reset", rst_n=0)
    cycle(rst_n=0)
    read(MSTATUS, "reset values: mstatus = MPP 11 only; misa; everything else 0")
    for a in (MISA, MIE, MTVEC, MSCRATCH, MEPC, MCAUSE, MTVAL, MIP) + IDS:
        read(a)
    read(MCYCLE, "mcycle counts every cycle after reset; minstret counts nothing yet")
    read(MCYCLE)
    read(MINSTRET)
    read(MCYCLEH)

    lines.append("// WRITE, SET, CLEAR on every writable CSR; unused bits read 0")
    for a, pattern in ((MSTATUS, MASK), (MIE, MASK), (MTVEC, MASK), (MSCRATCH, 0xA5A55A5A), (MEPC, 0x12345677),
                       (MCAUSE, 0x8000000B), (MTVAL, 0xDEADBEEF)):
        write(a, pattern)
        read(a)
        write(a, 0x00F0F00F, SET)
        read(a)
        write(a, 0xFFFF0000, CLEAR)
        read(a)
        write(a, 0)
    write(MSTATUS, 0x88, comment="mstatus: MIE and MPIE are the only writable bits")
    read(MSTATUS)
    write(MSTATUS, 0x80, CLEAR)
    read(MSTATUS)
    write(MSTATUS, 0)

    lines.append("// misa and mip ignore writes, which are legal (not in the read-only space)")
    write(MISA, 0)
    read(MISA)
    write(MIP, MASK)
    read(MIP)
    read(MIP, "mip.MEIP follows the interrupt lines", irq=1)
    read(MIP, irq=2)
    read(MIP, irq=3)

    lines.append("// read-only space [11:10] = 11: a write attempt is illegal, a plain read is not")
    for a in (CYCLE, INSTRETH, 0xF14):
        cycle(addr=a, op=SET, wdata=0, attempt=0)
        cycle(addr=a, op=WRITE, wdata=0x55, attempt=1, we=0)
    lines.append("// unimplemented addresses are illegal and read 0")
    for a in (0x000, 0x001, 0x302, 0x303, 0x7C0, 0xB01, 0xB03, 0xC03, 0xF15, 0xFFF, 0x7B0):
        read(a)
    lines.append("// attempt without we: legality only, no write")
    write(MSCRATCH, 0x11111111)
    write(MSCRATCH, 0x22222222, we=0)
    read(MSCRATCH)

    lines.append("// trap entry: mepc (low bits dropped), mcause, mtval; MPIE <- MIE, MIE <- 0")
    write(MSTATUS, 0x8)
    write(MIE, 0x800)
    read(MSTATUS)
    cycle(trap=1, cause=11, epc=0x00000077, val=0)
    read(MSTATUS)
    read(MEPC)
    read(MCAUSE)
    read(MTVAL)
    lines.append("// MRET: MIE <- MPIE, MPIE <- 1")
    cycle(mret=1)
    read(MSTATUS)
    cycle("a trap with MIE = 0 leaves MPIE = 0", trap=1, cause=2, epc=0x1000, val=0)
    write(MSTATUS, 0, CLEAR, we=0)
    cycle(trap=1, cause=4, epc=0x2004, val=0x20000001)
    read(MSTATUS)
    read(MTVAL)
    cycle(mret=1)
    read(MSTATUS)
    lines.append("// priority: trap over a CSR write in the same cycle, MRET over a CSR write")
    cycle(addr=MSCRATCH, wdata=0x33333333, attempt=1, we=1, trap=1, cause=3, epc=0x44, val=0x44)
    read(MSCRATCH)
    read(MCAUSE)
    cycle(addr=MSCRATCH, wdata=0x44444444, attempt=1, we=1, mret=1)
    read(MSCRATCH)

    lines.append("// irq_pending = MIE AND MEIE AND MEIP")
    for mie in (0, 1):
        for meie in (0, 1):
            write(MSTATUS, mie << 3)
            write(MIE, meie << 11)
            for irq in (0, 1, 2):
                read(MSTATUS, irq=irq)

    lines.append("// counters: writes to either half replace it and suppress the increment in that cycle")
    write(MCYCLE, 0xFFFFFFFE)
    read(MCYCLE)
    read(MCYCLE)
    read(MCYCLEH)
    read(CYCLEH)
    read(TIMEH)
    write(MCYCLEH, 0x00000007)
    read(MCYCLEH)
    read(CYCLE)
    read(TIME)
    write(MINSTRET, 0xFFFFFFFF)
    read(MINSTRET)
    cycle(addr=MINSTRET, retire=1)
    read(MINSTRETH)
    read(INSTRETH)
    for _ in range(3):
        cycle(addr=INSTRET, retire=1)
    read(INSTRET)
    write(MINSTRETH, 0x00000100)
    cycle(addr=MINSTRETH, attempt=1, we=1, op=WRITE, wdata=0x00000200, retire=1)
    read(MINSTRETH)
    read(MINSTRET)

    lines.append("// random sequence")
    rnd = random.Random(SEED)
    addrs = sorted(IMPLEMENTED) + [0x000, 0x302, 0x7C0, 0xC03]
    for _ in range(600):
        kind = rnd.random()
        addr = rnd.choice(addrs)
        op = rnd.choice([WRITE, SET, CLEAR])
        wdata = rnd.choice([rnd.getrandbits(32), 0, MASK, 1 << rnd.randrange(32)])
        attempt = int(rnd.random() < 0.6)
        we = int(attempt and rnd.random() < 0.8 and addr in IMPLEMENTED and (addr >> 10) != 3)
        trap = int(kind < 0.05)
        mret = int(0.05 <= kind < 0.09)
        cycle(addr=addr, op=op, wdata=wdata, attempt=attempt, we=we, trap=trap,
              cause=rnd.choice([0, 2, 3, 4, 6, 11, 0x8000000B]), epc=rnd.getrandbits(32),
              val=rnd.getrandbits(32), mret=mret, retire=int(rnd.random() < 0.5), irq=rnd.randrange(4))
    return lines


def write_csr_vectors():
    head = [
        "// csr_file test vectors (generated by sw/gen_unit_vectors.py)",
        "// format: rst_n addr(hex) op(bin) wdata(hex) attempt we trap_take trap_cause(hex) trap_epc(hex)",
        "//         trap_val(hex) mret_take retire irq_lines(bin)",
        "//         expected: csr_rdata(hex) csr_illegal mtvec_out(hex) mepc_out(hex) irq_pending, then wait_type",
        "// Each clock cycle is two lines: wait_type 0 checks the combinational outputs for the",
        "// cycle's inputs, wait_type 1 applies the rising edge with the same inputs (x = don't care).",
        "// op: 00 WRITE, 01 SET, 10 CLEAR. mcycle counts every edge after reset.",
    ]
    with open("vectors/csr_file_vectors.txt", "w") as f:
        f.write("\n".join(head + csr_vectors()) + "\n")


# ---------------------------------------------------------------------------
# Trap unit
# ---------------------------------------------------------------------------
def trap_model(v):
    """(trap_req, cause, mtval) for the instruction described by v."""
    f3 = v["funct3"] & 3
    lo = v["addr_lo"]
    misaligned = (f3 == 2 and lo != 0) or (f3 == 1 and lo & 1)
    if not v["valid"]:
        return 0, None, None
    if v["irq"] and v["irq_ok"]:
        return 1, 0x8000000B, 0
    if v["illegal"] or (v["csr"] and v["csr_illegal"]):
        return 1, 2, 0
    if v["ebreak"]:
        return 1, 3, v["pc"]
    if v["ecall"]:
        return 1, 11, 0
    if v["rd"] and misaligned:
        return 1, 4, v["addr"]
    if v["wr"] and misaligned:
        return 1, 6, v["addr"]
    return 0, None, None


def trap_vectors():
    rnd = random.Random(SEED + 1)
    lines = []

    def vec(comment=None, **kw):
        v = dict(valid=1, pc=0x100, illegal=0, ecall=0, ebreak=0, csr=0, csr_illegal=0, rd=0, wr=0,
                 funct3=2, addr_lo=0, addr=0x20000000, irq=0, irq_ok=1)
        v.update(kw)
        if comment:
            lines.append("// " + comment)
        req, cause, val = trap_model(v)
        exp = "%d %s %s" % (req, "%08X" % cause if req else "xxxxxxxx", "%08X" % val if req else "xxxxxxxx")
        lines.append("%d %08X %d %d %d %d %d %d %d %d%d%d %d%d %08X %d %d  %s" % (
            v["valid"], v["pc"], v["illegal"], v["ecall"], v["ebreak"], v["csr"], v["csr_illegal"],
            v["rd"], v["wr"], v["funct3"] >> 2, (v["funct3"] >> 1) & 1, v["funct3"] & 1,
            v["addr_lo"] >> 1, v["addr_lo"] & 1, v["addr"], v["irq"], v["irq_ok"], exp))

    vec("no trap: an ordinary instruction")
    vec("bubble: nothing traps, whatever the controls say", valid=0, ecall=1, irq=1)
    vec("illegal instruction, cause 2, mtval 0", illegal=1)
    vec("CSR access to an illegal CSR", csr=1, csr_illegal=1)
    vec("csr_illegal without a CSR access does not trap", csr=0, csr_illegal=1)
    vec("EBREAK, cause 3, mtval = PC", ebreak=1, pc=0x1234)
    vec("ECALL, cause 11 (machine mode, never 8)", ecall=1)
    lines.append("// loads and stores: word needs addr[1:0] = 0, halfword addr[0] = 0, bytes never trap")
    for rd, wr in ((1, 0), (0, 1)):
        for f3 in (0, 1, 2, 4, 5):
            if wr and f3 > 2:
                continue
            for lo in range(4):
                vec(rd=rd, wr=wr, funct3=f3, addr_lo=lo, addr=0x20000100 | lo)
    vec("the misalignment check uses addr_lo, the fast adder output", rd=1, funct3=2, addr_lo=1, addr=0x20000100)
    vec(rd=1, funct3=2, addr_lo=0, addr=0x20000101)
    lines.append("// interrupt: taken when allowed, before any exception of the same instruction")
    vec(irq=1)
    vec(irq=1, irq_ok=0)
    vec(irq=1, ecall=1)
    vec(irq=1, irq_ok=0, ecall=1)
    vec(irq=1, illegal=1)
    vec(irq=1, rd=1, funct3=2, addr_lo=1)
    vec(valid=0, irq=1)
    lines.append("// random")
    for _ in range(400):
        vec(valid=int(rnd.random() < 0.9), pc=rnd.getrandbits(32) & ~1, illegal=int(rnd.random() < 0.1),
            ecall=int(rnd.random() < 0.1), ebreak=int(rnd.random() < 0.1), csr=int(rnd.random() < 0.2),
            csr_illegal=int(rnd.random() < 0.3), rd=int(rnd.random() < 0.3), wr=int(rnd.random() < 0.3),
            funct3=rnd.choice([0, 1, 2, 4, 5]), addr_lo=rnd.randrange(4), addr=rnd.getrandbits(32),
            irq=int(rnd.random() < 0.2), irq_ok=int(rnd.random() < 0.7))
    return lines


def write_trap_vectors():
    head = [
        "// trap_unit test vectors (generated by sw/gen_unit_vectors.py)",
        "// format: valid pc(hex) illegal is_ecall is_ebreak csr_access csr_illegal mem_read mem_write",
        "//         funct3(bin) mem_addr_lo(bin) mem_addr(hex) irq_pending irq_allowed",
        "//         expected: trap_req trap_cause(hex) trap_val(hex)   (x = don't care)",
        "// Combinational: apply, wait 10 ns, compare.",
    ]
    with open("vectors/trap_unit_vectors.txt", "w") as f:
        f.write("\n".join(head + trap_vectors()) + "\n")


if __name__ == "__main__":
    write_csr_vectors()
    write_trap_vectors()

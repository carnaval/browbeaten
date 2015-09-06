macro ftdi(func, ret, args, ctx, rest...)
    @assert isa(func, Symbol)
    tt = eval(args)
    quote
        ret = ccall(($(Meta.quot(symbol("ftdi_",string(func)))), "libftdi"), $ret, (Ptr{Void},$(tt...)), $ctx, $(rest...))
        if ret < 0
            err = bytestring(ccall((:ftdi_get_error_string, "libftdi"), Ptr{UInt8}, (Ptr{Void},), $ctx))
            error("Error (code:$(-ret)) $err")
        end
        ret
    end
end

const ST_DESYNC = 0
const ST_RESET = 1
const ST_SHIFT_DR = 2
const ST_SHIFT_IR = 3
type JTAG
    ftdi_ctx :: Vector{UInt8}
    state :: Int
end
const FTDI_CTX_SZ = 112
const ALTERA_USB_BLASTER = (0x09fb, 0x6001)

function close(jtag)
    @ftdi(usb_close, Int32, (), jtag.ftdi_ctx)
    @ftdi(deinit, Int32, (), jtag.ftdi_ctx) # returns void but well
end
function JTAG(usb_id)
    ctx = zeros(UInt8, 112)
    @ftdi(init, Int32, (), ctx)
    @ftdi(usb_open, Int32, (UInt32, UInt32), ctx, usb_id[1], usb_id[2])
    @ftdi(set_latency_timer, Int32, (Int32,), ctx, 2)
    @ftdi(disable_bitbang, Int32, (), ctx)
    @ftdi(set_baudrate, Int32, (Int32,), ctx, 300000)
    @ftdi(usb_purge_buffers, Int32, (), ctx)
    j = JTAG(ctx, ST_DESYNC)
    reset(j)
    j
end

const TCK = 0x1
const TMS = 0x2
const OTHER_BITS = (0x4 | 0x8)
const TDI = 0x10
const LED = 0x20
const READ = 0x40
const SHMODE = 0x80

const N_RETRY = 10

const _dataref = Ref(0x0)
function cycle(jtag::JTAG, data::UInt8)
    _dataref[] = data
    retry = 0
    while retry <= N_RETRY &&
          @ftdi(write_data, Int32, (Ptr{UInt8},Int32), jtag.ftdi_ctx, _dataref, 1) == 0
        retry += 1
    end
    (data & READ) != 0 || return 0x0
    retry = 0
    while retry <= N_RETRY &&
          @ftdi(read_data, Int32, (Ptr{UInt8},Int32), jtag.ftdi_ctx, _dataref, 1) == 0
        retry += 1
    end
    _dataref[]
end
const TRACE = false
function clock(jtag::JTAG, data)
    cycle(jtag, (LED | OTHER_BITS | convert(UInt8, data)) & ~READ)
    res = cycle(jtag, LED | OTHER_BITS | TCK | convert(UInt8, data)) != 0
    TRACE && println("CLK TDI:", (data & TDI) != 0 ? "1" : "0", " TDO:", res ? "1" : "0", " ", (data & TMS) != 0 ? "TMS" : "")
    res
end
function clock(jtag::JTAG, cmds...)
    for cmd in cmds
        clock(jtag, cmd)
    end
end
immutable Bits
    n :: Int
end
function shift(jtag::JTAG, n::Bits; last = true)
    x = BitArray(n.n)
    for i = 1:n.n
        x[i] = clock(jtag, READ | (last && i == n.n ? TMS : 0))
    end
    x
end
function shift{T}(jtag::JTAG, ::Type{T}; last = true)
    x = zero(T)
    n = sizeof(T)*8
    for i=1:n
        x = x | (convert(T,clock(jtag, READ | (last && i == n ? TMS : 0))) << (i-1))
    end
    x
end
function shift(jtag::JTAG, bits::BitArray; last = true)
    n = length(bits)
    for i = 1:n
        bit = bits[i]
        clock(jtag, (bit ? TDI : 0) | (last && i == n ? TMS : 0))
    end
end

function reset(jtag::JTAG)
    if jtag.state != ST_RESET
        clock(jtag, TMS, TMS, TMS, TMS, TMS, 0)
        jtag.state = ST_RESET
    end
end
function begin_shift_dr(jtag::JTAG)
    @assert jtag.state == ST_RESET
    clock(jtag, TMS, 0, 0)
    jtag.state = ST_SHIFT_DR
end
function begin_shift_ir(jtag::JTAG)
    @assert jtag.state == ST_RESET
    clock(jtag, TMS, TMS, 0, 0)
    jtag.state = ST_SHIFT_IR
end
function end_shift(jtag::JTAG)
    @assert jtag.state == ST_SHIFT_DR || jtag.state == ST_SHIFT_IR
    clock(jtag, TMS, 0)
    jtag.state = ST_RESET
end
function shift_ir(jtag::JTAG, data...)
    begin_shift_ir(jtag)
    r = shift(jtag, data...)
    end_shift(jtag)
    r
end
function shift_dr(jtag::JTAG, data...)
    begin_shift_dr(jtag)
    r = shift(jtag, data...)
    end_shift(jtag)
    r
end
#=
shift(in, out)
in = bitarray | bits+len
out = length(bitarray) | length(bits)
(::BitArray) :: BitArray
(::BitArray, T) :: T
(::Int) :: BitArray
(::Int, T) :: T
(::Int, val,  
begin_shift(DR)
end_shift()
=#
function chain_length(jtag::JTAG, max_len = 30)
    shift_ir(jtag, trues(max_len))
    begin_shift_dr(jtag)
    shift(jtag, falses(max_len), last=false)
    n = 0
    while !clock(jtag, TDI|READ)
        n += 1
    end
    clock(jtag, TMS)
    end_shift(jtag)
    n
end

function bitarray(x, n)
    bits = BitArray(n)
    for i=1:n
        bits[i] = (x&1) != 0
        x >>= 1
    end
    bits
end
function integer(T::Type, bits::BitArray)
    x = zero(T)
    for i=length(bits):-1:1
        x = (x<<1) | convert(T,bits[i])
    end
    x
end

function idcode(jtag::JTAG)
    shift_ir(jtag, bitarray(0b0000000110, 10))
    shift_dr(jtag, UInt32)
end
type VJHub
    jtag :: JTAG
    nodes
    ir_len :: Int
    addr_width :: Int
end
immutable VJNode
    hub :: VJHub
    instance :: UInt
    addr :: UInt
end
function vj_info_line(jtag::JTAG)
    a = BitArray(0)
    for i=1:8
        append!(a, shift_dr(jtag, Bits(4)))
    end
    map(bits -> integer(UInt, bits), (a[1:8], a[9:19], a[20:27], a[28:32]))
end
const VJ_USR0 = bitarray(12, 10)
const VJ_USR1 = bitarray(14, 10)
function vj_hub_info(jtag::JTAG)
    shift_ir(jtag, VJ_USR1)
    shift_dr(jtag, bitarray(0, 64))
    shift_ir(jtag, VJ_USR0)
    ir_length, magic, n_nodes, hub_version = vj_info_line(jtag)
    addr_width = ceil(Int, log2(1+n_nodes))
    println("Hub found. Mfct 0x", hex(magic), " v", dec(hub_version), " with ", dec(n_nodes), " nodes. IR: ", dec(ir_length), " bits. Bus: ", dec(addr_width), " bits")
    nodes = Array(VJNode, n_nodes)
    hub = VJHub(jtag, nodes, ir_length, addr_width)
    for i=1:n_nodes
        node_inst, magic, node_id, node_version = vj_info_line(jtag)
        println("\tnode ", dec(node_inst), ":", node_id, ". Mfct ", hex(magic), " v", dec(node_version))
        nodes[i] = VJNode(hub, node_inst, i)
    end
    hub
end
function shift_ir(vj::VJNode, data...)
    jtag = vj.hub.jtag
    shift_ir(jtag, VJ_USR1)
    begin_shift_dr(jtag)
    res = shift(jtag, data..., last = false)
    shift(jtag, bitarray(vj.addr, vj.hub.addr_width))
    end_shift(jtag)
    res
end
function shift_dr(vj::VJNode, data...)
    jtag = vj.hub.jtag
    shift_ir(jtag, VJ_USR0)
    begin_shift_dr(jtag)
    res = shift(jtag, data...)
    end_shift(jtag)
    res
end

function set_addr(j, data...)
    shift_ir(j, bitpack([1, 0, 1, 1]))
    shift_dr(j, data...)
end
function store(j, data...)
    shift_ir(node, bitpack([0, 0, 0, 1]))
    shift_dr(node, data...)
end
function load(j, data...)
    shift_ir(node, bitpack([1, 0, 0, 1]))
    shift_dr(node, data...)
end
function host2dev(j, base::Int, data :: Vector{UInt16})
    for i in eachindex(data)
        set_addr(j, bitarray(i+base, 9))
        store(j, bitarray(data[i], 16))
    end
end
function dev2host(j, base::Int, len::Int)
    data = Array(UInt16, len)
    for i=1:len
        set_addr(j, bitarray(base+i,9))
        data[i] = load(j, UInt16)
    end
    data
end
function core_ctrl(j, running::Bool)
    shift_ir(node, bitpack([0, 0, 1, 1]))
    shift_dr(node, bitpack([running]))
end
jtag = JTAG(ALTERA_USB_BLASTER)
reset(jtag)
println("chain length: ", chain_length(jtag))
println("IDCODE: ", hex(idcode(jtag)))
hub = vj_hub_info(jtag)
node = hub.nodes[1]
if false
#=set_addr(node, bitarray(0, 9))
read(STDIN, Char)
store(node, trues(16))
read(STDIN, Char)
@show map(Int,load(node, Bits(16)))=#
@time @show dev2host(node, 0, 12)
#=host2dev(node, 0, UInt16[1,2,3,4,5, 0xffff])
@show dev2host(node, 0, 12)=#
shift_ir(node, bitpack([0, 0, 1, 1]))
shift_dr(node, bitpack([1]))
sleep(3)
shift_dr(node, bitpack([0]))
#@show shift_dr(node, Bits(100))
#=for i=1:100
    shift_ir(node, @show(bitrand(4)))
    read(STDIN, Char)
    #sleep(0.1)
    end=#
end
atexit(() -> close(jtag))

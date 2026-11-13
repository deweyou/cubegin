# 打乱名称对照

2026-11-03 对照 csTimer 官方仓库 master 的中英文 scrdata。此表记录展示名称对应关系，
不表示生成算法、分布、Case 定义或 WCA 认证相同。App 在设置中提供简体中文和 English，
两套项目名称均来自下表。SDK ID、成绩中保存的 ID 和生成算法不变。

- 中文来源：https://github.com/cs0x7f/cstimer/blob/master/src/lang/zh-cn.js
- 英文来源：https://github.com/cs0x7f/cstimer/blob/master/src/lang/en-us.js
- 上游项目：https://github.com/cs0x7f/cstimer ，GPL-3.0，csTimer contributors。

抓取文件 SHA-256（master 会变化）：

- `zh-cn.js`: `21a80af3009ada7341b24acdbf56de99dcbe9f0e1fda4c0d2b587f33275c9ff1`
- `en-us.js`: `2ba55c50e882e3043763a886348dbdd3ebc9abfe8dc22cce3fc94b7267214393`

## 分类

按 csTimer 使用 3x3x3、3x3x3 CFOP、3x3x3 Roux、3x3x3 Mehta、3x3x3子集等名称。
四阶方法训练归入 4x4x4 Yau/Hoya；三阶棱块/角块训练归回 3x3x3。
3x3x3 状态训练是本产品补充分组；FTO 是上游长名称的紧凑展示。
模式仍使用用户确定的「标准 / 训练」，不照搬上游 WCA 分区名称。

## 项目

| SDK ID | csTimer ID | 中文展示 | 英文参考 | 中文分组 | 英文分组 |
|---|---|---|---|---|---|
| `222` | `222so` | 二阶速拧 | 2x2x2 | 标准 | Standard |
| `333` | `333` | 三阶速拧 | 3x3x3 | 标准 | Standard |
| `333oh` | `333oh` | 三阶单手 | 3x3 oh | 标准 | Standard |
| `333bld` | `333ni` | 三阶盲拧 | 3x3 bld | 标准 | Standard |
| `444` | `444wca` | 四阶速拧 | 4x4x4 | 标准 | Standard |
| `444bld` | `444bld` | 四阶盲拧 | 4x4 bld | 标准 | Standard |
| `555` | `555wca` | 五阶速拧 | 5x5x5 | 标准 | Standard |
| `555bld` | `555bld` | 五阶盲拧 | 5x5 bld | 标准 | Standard |
| `666` | `666wca` | 六阶速拧 | 6x6x6 | 标准 | Standard |
| `777` | `777wca` | 七阶速拧 | 7x7x7 | 标准 | Standard |
| `clock` | `clkwca` | 魔表 | clock | 标准 | Standard |
| `minx` | `mgmp` | 五魔方 | megaminx | 标准 | Standard |
| `pyram` | `pyrso` | 金字塔 | pyraminx | 标准 | Standard |
| `skewb` | `skbso` | 斜转魔方 | skewb | 标准 | Standard |
| `sq1` | `sqrs` | Square-1 | sq1 | 标准 | Standard |
| `fto` | `ftoso` | FTO | FTO | 标准 | Standard |
| `222.cll` | `222eg0` | CLL | CLL | 2x2x2 | 2x2x2 |
| `222.eg1` | `222eg1` | EG1 | EG1 | 2x2x2 | 2x2x2 |
| `222.eg2` | `222eg2` | EG2 | EG2 | 2x2x2 | 2x2x2 |
| `222.pbl` | 无直接对应项 | PBL | PBL | 2x2x2 | 2x2x2 |
| `222.tcll_plus` | `222tcp` | TCLL+ | TCLL+ | 2x2x2 | 2x2x2 |
| `222.tcll_minus` | `222tcn` | TCLL- | TCLL- | 2x2x2 | 2x2x2 |
| `222.ls` | `222lsall` | LS | LS | 2x2x2 | 2x2x2 |
| `222.no_bar` | `222nb` | 无连色 | No Bar | 2x2x2 | 2x2x2 |
| `222.teg1` | 无直接对应项 | TEG-1 | TEG-1 | 2x2x2 | 2x2x2 |
| `222.teg2` | 无直接对应项 | TEG-2 | TEG-2 | 2x2x2 | 2x2x2 |
| `333.edges_only` | `edges` | 棱块训练 | edges only | 3x3x3 | 3x3x3 |
| `333.corners_only` | `corners` | 角块训练 | corners only | 3x3x3 | 3x3x3 |
| `333.ll` | `ll` | 顶层训练 | last layer | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.pll` | `pll` | PLL | PLL | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.oll` | `oll` | OLL | OLL | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.lsll` | `lsll2` | F2L单组 | last slot + last layer | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.zbll` | `zbll` | ZBLL | ZBLL | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.coll` | `coll` | COLL | COLL | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.cll` | `cll` | CLL | CLL | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.ell` | `ell` | ELL | ELL | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.2gll` | `2gll` | 2GLL | 2GLL | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.zzll` | `zzll` | ZZLL | ZZLL | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.zbls` | `zbls` | ZBLS | ZBLS | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.eols` | `eols` | EOLS | EOLS | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.wvls` | `wvls` | WVLS | WVLS | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.vls` | `vls` | VLS | VLS | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.f2l` | `f2l` | F2L训练 | cross solved | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.easy_cross` | `easyc` | 简单十字 | easy cross | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.easy_xcross` | `easyxc` | 简单XCross | easy xcross | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.eoline` | `eoline` | EOLine | EOLine | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.eo_cross` | `eocross` | EO Cross | EO Cross | 3x3x3 CFOP | 3x3x3 CFOP |
| `333.edge_permutation` | 无直接对应项 | 棱块排列 | edge permutation | 3x3x3 状态训练 | 3x3x3 state training |
| `333.edge_orientation` | 无直接对应项 | 棱块朝向 | edge orientation | 3x3x3 状态训练 | 3x3x3 state training |
| `333.corner_permutation` | 无直接对应项 | 角块排列 | corner permutation | 3x3x3 状态训练 | 3x3x3 state training |
| `333.corner_orientation` | 无直接对应项 | 角块朝向 | corner orientation | 3x3x3 状态训练 | 3x3x3 state training |
| `333.permutation_only` | 无直接对应项 | 仅排列 | permutation only | 3x3x3 状态训练 | 3x3x3 state training |
| `333.orientation_only` | 无直接对应项 | 仅朝向 | orientation only | 3x3x3 状态训练 | 3x3x3 state training |
| `333.three_edge_cycle` | 无直接对应项 | 三棱循环 | three edge cycle | 3x3x3 状态训练 | 3x3x3 state training |
| `333.three_corner_cycle` | 无直接对应项 | 三角循环 | three corner cycle | 3x3x3 状态训练 | 3x3x3 state training |
| `333.roux.second_block` | `sbrx` | 2nd Block | 2nd Block | 3x3x3 Roux | 3x3x3 Roux |
| `333.roux.cmll` | `cmll` | CMLL | CMLL | 3x3x3 Roux | 3x3x3 Roux |
| `333.roux.lse` | `lse` | LSE | LSE | 3x3x3 Roux | 3x3x3 Roux |
| `333.roux.lse_mu` | `lsemu` | LSE <M, U> | LSE <M, U> | 3x3x3 Roux | 3x3x3 Roux |
| `333.mehta.3qb` | `mt3qb` | 3QB | 3QB | 3x3x3 Mehta | 3x3x3 Mehta |
| `333.mehta.eole` | `mteole` | EOLE | EOLE | 3x3x3 Mehta | 3x3x3 Mehta |
| `333.mehta.tdr` | `mttdr` | TDR | TDR | 3x3x3 Mehta | 3x3x3 Mehta |
| `333.mehta.6cp` | `mt6cp` | 6CP | 6CP | 3x3x3 Mehta | 3x3x3 Mehta |
| `333.mehta.cdrll` | `mtcdrll` | CDRLL | CDRLL | 3x3x3 Mehta | 3x3x3 Mehta |
| `333.mehta.l5ep` | `mtl5ep` | L5EP | L5EP | 3x3x3 Mehta | 3x3x3 Mehta |
| `333.mehta.ttll` | `ttll` | TTLL | TTLL | 3x3x3 Mehta | 3x3x3 Mehta |
| `333.subset.ru` | `2gen` | 2-generator R,U | 2-generator R,U | 3x3x3子集 | 3x3x3 subsets |
| `333.subset.lu` | `2genl` | 2-generator L,U | 2-generator L,U | 3x3x3子集 | 3x3x3 subsets |
| `333.subset.fru` | `3gen_F` | 3-generator F,R,U | 3-generator F,R,U | 3x3x3子集 | 3x3x3 subsets |
| `333.subset.rul` | `3gen_L` | 3-generator R,U,L | 3-generator R,U,L | 3x3x3子集 | 3x3x3 subsets |
| `333.subset.rrwu` | `RrU` | 3-generator R,r,U | 3-generator R,r,U | 3x3x3子集 | 3x3x3 subsets |
| `333.subset.mu` | `roux` | Roux-generator M,U | Roux-generator M,U | 3x3x3子集 | 3x3x3 subsets |
| `333.subset.half_turn` | `half` | half turns only | half turns only | 3x3x3子集 | 3x3x3 subsets |
| `333.subset.domino` | `333drud` | Domino Subgroup | Domino Subgroup | 3x3x3子集 | 3x3x3 subsets |
| `444.edge_pairing` | `4edge` | 对棱训练 | 4x4x4 edges | 4x4x4 | 4x4x4 |
| `444.subset.rruu` | `RrUu` | R,r,U,u | R,r,U,u | 4x4x4 | 4x4x4 |
| `444.ll` | `444ll` | Last layer | Last layer | 4x4x4 | 4x4x4 |
| `444.ell` | `444ell` | ELL | ELL | 4x4x4 | 4x4x4 |
| `444.edges_only` | `444edo` | Edge only | Edge only | 4x4x4 | 4x4x4 |
| `444.centers_only` | `444cto` | Center only | Center only | 4x4x4 | 4x4x4 |
| `444.yau.ud_centers` | `444ctud` | UD center solved | UD center solved | 4x4x4 Yau/Hoya | 4x4x4 Yau/Hoya |
| `444.yau.ud_3_edges` | `444ud3c` | UD+3E solved | UD+3E solved | 4x4x4 Yau/Hoya | 4x4x4 Yau/Hoya |
| `444.yau.last_8_dedges` | `444l8e` | Last 8 dedges | Last 8 dedges | 4x4x4 Yau/Hoya | 4x4x4 Yau/Hoya |
| `444.hoya.rl_centers` | `444ctrl` | RL center solved | RL center solved | 4x4x4 Yau/Hoya | 4x4x4 Yau/Hoya |
| `444.hoya.rldx_centers` | `444rlda` | RLDX center solved | RLDX center solved | 4x4x4 Yau/Hoya | 4x4x4 Yau/Hoya |
| `444.hoya.rldx_cross` | `444rlca` | RLDX cross solved | RLDX cross solved | 4x4x4 Yau/Hoya | 4x4x4 Yau/Hoya |
| `444.poll` | `444poll` | POLL | POLL | 4x4x4 Yau/Hoya | 4x4x4 Yau/Hoya |
| `444.ppll` | `444ppll` | PPLL | PPLL | 4x4x4 Yau/Hoya | 4x4x4 Yau/Hoya |
| `555.edge_pairing` | `5edge` | 对棱训练 | 5x5x5 edges | 5x5x5 | 5x5x5 |
| `666.edge_pairing` | `6edge` | 对棱训练 | 6x6x6 edges | 6x6x6 | 6x6x6 |
| `777.edge_pairing` | `7edge` | 对棱训练 | 7x7x7 edges | 7x7x7 | 7x7x7 |
| `minx.subset.ru` | `minx2g` | 2-generator R,U | 2-generator R,U | 五魔方 | Megaminx |
| `minx.s2l` | `mgms2l` | S2L | S2L | 五魔方 | Megaminx |
| `minx.lsll` | `mlsll` | last slot + last layer | last slot + last layer | 五魔方 | Megaminx |
| `minx.pll` | `mgmpll` | PLL | PLL | 五魔方 | Megaminx |
| `minx.ll` | `mgmll` | Last Layer | Last Layer | 五魔方 | Megaminx |
| `pyram.l4e` | `pyrl4e` | L4E | L4E | 金字塔 | Pyraminx |
| `pyram.four_tips` | `pyr4c` | 4 tips | 4 tips | 金字塔 | Pyraminx |
| `pyram.no_bar` | `pyrnb` | No bar | No bar | 金字塔 | Pyraminx |
| `skewb.l2l` | `skbll` | 顶层训练 | last layer | Skewb | Skewb |
| `skewb.no_bar` | `skbnb` | No bar | No bar | Skewb | Skewb |
| `sq1.cube_shape` | 无直接对应项 | 方形状态 | Cube shape | Square-1 | Square-1 |
| `sq1.csp` | `sqrcsp` | CSP | CSP | Square-1 | Square-1 |
| `sq1.pbl` | 无直接对应项 | PBL | PBL | Square-1 | Square-1 |
| `fto.l3t` | `ftol3t` | L3T | L3T | FTO | FTO (Face-Turning Octahedron) |
| `fto.l3t_lbt` | `ftol4t` | L3T+LBT | L3T+LBT | FTO | FTO (Face-Turning Octahedron) |
| `fto.tcp` | `ftotcp` | TCP | TCP | FTO | FTO (Face-Turning Octahedron) |
| `fto.edges_only` | `ftoedge` | edges only | edges only | FTO | FTO (Face-Turning Octahedron) |
| `fto.centers_only` | `ftocent` | centers only | centers only | FTO | FTO (Face-Turning Octahedron) |
| `fto.corners_only` | `ftocorn` | corners only | corners only | FTO | FTO (Face-Turning Octahedron) |

没有直接对应项的保留产品名称，不将 Square-1 PBL 直接改成 csTimer 的 PLL，也不将 Cube shape 对应到转步计量打乱。
二阶 PBL、TEG-1/2 与三阶状态细分同样作为产品补充保留。

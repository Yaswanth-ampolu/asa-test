---
{
  "section": "I",
  "section_title": "Appendix A: KeyEx Primitive – Mapping of Status Codes",
  "module": "Appendices",
  "depth": 1,
  "page_start": 304,
  "page_end": 305,
  "content_type": "primitive_def",
  "register_address": null,
  "tables": [
    {
      "id": "I-1",
      "title": "KeyEx–Mapping of Status Codes"
    }
  ],
  "figures": [],
  "source": "ASA_Technical_Specification_ver2.0.pdf"
}
---

# I Appendix A: KeyEx Primitive – Mapping of Status Codes

I Appendix A: KeyEx Primitive–Mapping of Status Codes
ce
n
o | et et
y y
ice ice et
et | ed
y | t ev ev y
e
ed | d d ice
e written | o o | re
h | each | al)
b | e y t t | t
d | is | ed | ev r | fo n
ic | e
ly | d | e
n | es | iz size
fin | ev ten ten o | b tio
t | t | Ks | lt y Slo ty
faile | o y fail d | Ks K s
ID o | rit rit | L | p
n | o | ed (op
rif w w en | L
tion | n | t | f writ | y L | Sa Ke | r
ion | t t | gh | at
correct | n ca | o | em
ip | ve o o | u
g UU | d | en | ritt | t
OK in | t | o | rted
n tio n | er | rted rted
u | w | o | erro
scr | ticat | a | b en man | o o | valid
ce | ta | ritt | t | p
e | b _0 n _1 n | o | p p
n | u | w | o m t | p | y Slo in fic
D | en | re | p p
o | Wro p | u o | t
t | To su
N th | fo ten | y n | N | su su Ke | eci
m | o | n | n
e | y DK y DK | n n
n
Au | b | m | U | sp
U U | y Slo
Co | Writ | u | n
ID -Ke -Ke g Ke
b b | Ke U
ce | U | in
n | U | xim
o | Su Su
N | Bind Ma
y written
vice vice
ad
De De
Alre
e
d
ID KeyEx Primitive
Co 0x00 0x10 0x11 0x12 0x13 0x20 0x21 0x30 0x40 0x41 0x42 0x43 0x50 0x51 0x52 0x53 0x60 0x61 0x62 0xFF
0x
install_UUID | x | x x | x
0x
read_UUID | x | x | x
0x
read_current_nonce x | x | x x x x | x
0x
read_status_keys | x | x
0x
read_status_keys_ext x | x
0x
setup_policy | x | x x | x
0x install_DK_0_unencryp
x | x x x x | x
ted
0x install_DK_1_unencryp
x | x x x x x | x
ted
0x install_DK_1_encrypte
x x x x x x x | x
d
0x
install_BK_encrypted x x x x x x x x x | x
0x install_BK_encrypted_
x x x x x x x x x | x
by_DK_1_only
0x
install_LKs_encrypted x x x x | x x x x x x x x x x | x
0x
change_LKs_KeySlot x x x x | x x x x
0x
report_status_LK | x | x
Table I-1: KeyEx–Mapping of Status Codes

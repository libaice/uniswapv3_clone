import math

def price_to_tick(p):
    return math.floor(math.log(p, 1.0001))

q96 = 2 ** 96

def price_to_sqrtp(p):
    return int(math.sqrt(p) * q96)

print(price_to_tick(5000)) 
print(price_to_tick(4545))
print(price_to_tick(5500)) 


# 85176

# print(q96)
# 79228162514264337593543950336

# print(price_to_sqrtp(5000))
# Pc 5602277097478614198912276234240

# print(price_to_sqrtp(4545))
# Pa 5341294542274603406682713227264

# print(price_to_sqrtp(5500))
# Pb 5875717789736564987741329162240

# calculate L
# print( price_to_sqrtp(5000) * price_to_sqrtp(5500) / ( price_to_sqrtp(5500) - price_to_sqrtp(5000) ) / q96)

# ----------------
sqrtp_low = price_to_sqrtp(4545)
sqrtp_cur = price_to_sqrtp(5000)
sqrtp_upp = price_to_sqrtp(5500)

def liquidity0(amount, pa, pb):
    if(pa > pb):
        pa, pb = pb, pa
    return (amount * (pa * pb) / q96) / (pb - pa)

def liquidity1(amount, pa, pb):
    if(pa > pb):
        pa, pb = pb, pa
    return amount * q96 / (pb - pa)


eth = 10**18
amount_eth = 1 * eth
amount_usdc = 5000 * eth

liq0 = liquidity0(amount_eth, sqrtp_cur, sqrtp_upp)
liq1 = liquidity1(amount_usdc, sqrtp_cur, sqrtp_low)
# print(liq0)
# print(liq1)
liq = min(liq0, liq1)
print("liq",liq )
# 1517.8823437515099e+18

# ----------------
def calc_amount0(liq, pa, pb):
    if(pa > pb):
        pa, pb = pb, pa
    return int(liq* q96 * (pb-pa) / (pa * pb))

def calc_amount1(liq, pa, pb):
    if(pa > pb):
        pa, pb = pb, pa
    return int(liq * (pb - pa) / q96)


amount0 = calc_amount0(liq, sqrtp_upp, sqrtp_cur)
amount1 = calc_amount1(liq, sqrtp_low, sqrtp_cur)

print(amount0)
# 998976618347425408

print(amount1)
# 5000 000000000000000000
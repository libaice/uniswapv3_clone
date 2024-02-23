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

print(q96)
# 79228162514264337593543950336

print(price_to_sqrtp(5000))
# 5602277097478614198912276234240
#include <cstdlib>
#include <new>
bool countAllocations = false;
std::size_t calls = 0, allocated = 0;
void* operator new(std::size_t n) {
    if (auto p = std::malloc(n ? n : 1)) {
        if (countAllocations) { ++calls; allocated += n; }
        return p;
    }
    throw std::bad_alloc();
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }

# Windows decision status

The current task settles semantic boundaries only. **Swift/C++ and GPU API remain
open.** WinUI 3 is a successful experiment with either Core, not a finalized product
UI. No product migration is started by these documents.

The final-choice wording introduced by `841d09c` is superseded at the owner's
request, with the original proposal retained in Git history. See
[Windows boundary](windows-architecture.md), [Core contract](../core-api.md),
[open questions](architecture-questions.md) and [repository evidence](repository-evidence.md).

| Area | Current status |
|---|---|
| C kernels | Existing shared implementation and tests; preserve it |
| Swift/C++ model Core | Both viable experiments; compare actual extracted data and the same bulk boundary before deciding |
| C ABI | Proven experimental host route; product signatures, ownership binding and error/version layout not fixed |
| UI | WinUI 3/C# spike works; real canvas/input/accessibility evidence still needed |
| GPU | Platform renderer boundary defined; no DirectX/Vulkan choice or implementation |
| Text/color | Core holds semantic data; native services behind adapters; engines/tolerances open |
| Packaging/update/recovery | Platform responsibilities; previous concrete plans are unimplemented proposals |
| `.comp` | Main synchronized: reader 1–12, presence-based save11/12. No independent format extension or migration |

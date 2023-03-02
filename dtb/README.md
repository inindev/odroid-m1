## linux device tree for the odroid m1

<br/>

**build device the tree for the odroid m1**
```
sh make_dtb.sh
```

<i>the build will produce the target file rk3568-odroid-m1.dtb</i>

<br/>

**optional: create symbolic links**
```
sh make_dtb.sh links
```

<i>convenience link to rk3568-odroid-m1.dts will be created in the project directory</i>

<br/>

**optional: clean target**
```
sh make_dtb.sh clean
```


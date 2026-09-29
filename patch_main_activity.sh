sed -i '/private val backgroundExecutor/a \    private lateinit var iconPackManager: IconPackManager' android/app/src/main/kotlin/co/za/launcher3/swavoti/MainActivity.kt
sed -i '/super.onCreate(savedInstanceState)/a \        iconPackManager = IconPackManager(this)' android/app/src/main/kotlin/co/za/launcher3/swavoti/MainActivity.kt

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../screens/categories_page.dart';
import '../screens/x_search_page.dart';
import '../theme.dart';

void openPhoneCategories(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) {
        return const Scaffold(
          backgroundColor: AppColors.navBar,
          body: SafeArea(
            child: ColoredBox(
              color: AppColors.bg,
              child: CategoriesPage(),
            ),
          ),
        );
      },
    ),
  );
}

void openPhoneSearch(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) {
        return const Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: XSearchPage(dialog: true),
          ),
        );
      },
    ),
  );
}

class PhoneSearchButton extends StatelessWidget {
  const PhoneSearchButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '搜索',
      onPressed: () => openPhoneSearch(context),
      icon: SvgPicture.asset(
        'assets/images/search.svg',
        width: 22.w,
        height: 22.w,
        colorFilter: const ColorFilter.mode(AppColors.text, BlendMode.srcIn),
      ),
    );
  }
}

class PhoneCategoryButton extends StatelessWidget {
  const PhoneCategoryButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '分类',
      onPressed: () => openPhoneCategories(context),
      icon: SvgPicture.asset(
        'assets/images/focus.svg',
        width: 22.w,
        height: 22.w,
        colorFilter: const ColorFilter.mode(AppColors.text, BlendMode.srcIn),
      ),
    );
  }
}

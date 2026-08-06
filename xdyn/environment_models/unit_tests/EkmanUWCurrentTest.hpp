/*
 * EkmanUWCurrentTest.hpp
 */

#ifndef EKMANUWCURRENTTEST_HPP_
#define EKMANUWCURRENTTEST_HPP_

#include "gtest/gtest.h"
#include <ssc/random_data_generator.hpp>

class EkmanUWCurrentTest : public ::testing::Test
{
    protected:
        EkmanUWCurrentTest();
        virtual ~EkmanUWCurrentTest();
        virtual void SetUp();
        virtual void TearDown();
        ssc::random_data_generator::DataGenerator a;
};

#endif /* EKMANUWCURRENTTEST_HPP_ */
